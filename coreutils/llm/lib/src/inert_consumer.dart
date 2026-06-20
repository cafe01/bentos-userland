/// The inert consumer — the shared core both `prompt` and `chat` are built on.
///
/// It embodies the coreutil's whole ontology (`llm` spec §1): it opens
/// `/dev/llm/<vendor>/<model>` via the boot layer and streams `infer`, never
/// touching keys, vendors, or drivers. The device is booted ONCE and reused
/// across turns — `chat` does not re-boot per turn.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:chat_inference/chat_inference.dart';

/// A booted, reusable handle on one `/dev/llm/*` device.
///
/// The consumer reaches Bentos through the raw syscall surface only —
/// `open/ioctl/write/read`, zero device sugar (the relay law, #33). The
/// `chat_inference` codec it pulls is userland flattening (CLI-constructed
/// records in, byte-stream framing out), never the `BentosChatDevice` sugar.
class InertConsumer {
  /// Raw syscall surface — used by [relayTurn] and [textTurn] for direct,
  /// zero-sugar device I/O.
  final Bentos _bentos;

  final String devicePath;

  InertConsumer(this._bentos, this.devicePath);

  /// Boots the in-process portal for [devicePath] once and returns a consumer
  /// over it. Throws [LlmBootException] if the path cannot be routed (malformed
  /// path / unknown vendor) — a missing credential is NOT raised here; it fails
  /// the later turn's `open` with EACCES (a [BentosException]).
  factory InertConsumer.forDevice(String devicePath) {
    final bentos = bootLlmDevice(devicePath);
    return InertConsumer(bentos, devicePath);
  }

  /// The casual register — text in, text out — over raw syscalls, zero codec
  /// on the wire (the relay law, #33). The CLI-constructed system + user
  /// messages are written as structured protobuf records (userland flattening);
  /// the device's unstructured text output is relayed verbatim to [out] and
  /// accumulated as UTF-8 into the returned string — so a caller holding a
  /// conversation (`llm chat`) can append the reply and carry context forward.
  ///
  /// Text mode carries no metadata: there is no `Complete` record on the text
  /// seam, so `-v` prints nothing here — `[model · stopReason · usage]` is a
  /// property of `--output-format typed`, where the consumer decodes it.
  ///
  /// [systemMessages] are prepended before [messages] (system role first); the
  /// caller passes the whole conversation so `llm chat` can carry multi-turn
  /// context across turns. [config] carries `maxTokens` / `temperature` /
  /// `streaming` ioctls.
  ///
  /// A `BentosException` (e.g. EACCES with no credential) propagates to the
  /// caller, surfaced exactly as a POSIX/IO error from behind the device.
  Future<String> textTurn(
    List<ChatMessage> messages, {
    List<ChatMessage> systemMessages = const [],
    ChatIOConfig config = const ChatIOConfig(),
    IOSink? out,
  }) async {
    out ??= stdout;
    // Input is CLI-constructed records (structured protobuf so system role is
    // carried separately); output is unstructured text relayed verbatim.
    final effectiveConfig = config.copyWith(
      inputFormat: Format.structured,
      inputEncoding: Encoding.protobuf,
      outputFormat: Format.unstructured,
    );

    final reply = StringBuffer();
    final fd = await _bentos.open(devicePath);
    try {
      for (final (cmd, payload) in configToIoctls(effectiveConfig)) {
        await _bentos.ioctl(fd, cmd, payload);
      }
      for (final m in [...systemMessages, ...messages]) {
        await _bentos.write(fd, encodeMessage(m));
      }

      while (true) {
        final raw = await _bentos.read(fd);
        if (raw.isEmpty) break;
        out.add(raw);
        reply.write(utf8.decode(raw, allowMalformed: true));
      }
      out.writeln(); // userland trailing newline after the turn
    } finally {
      await _bentos.close(fd);
    }
    return reply.toString();
  }

  /// Relay turn — pure POSIX I/O, zero codec of content on both seams.
  ///
  /// Used whenever `--input-format typed` OR `--output-format typed`. Input
  /// bytes from [typedStdin] (or prompt bytes from [textPrompt]) are written
  /// verbatim to the device; raw bytes from each `read()` are written verbatim
  /// to [out], with only the framing delimiter added by the coreutil.
  ///
  /// Three output cases (encoding is inert under `outputFormat=text`):
  /// - `outputFormat=text`:          raw passthrough, no per-record framing.
  /// - `outputFormat=typed, json`:   each record + `\n`.
  /// - `outputFormat=typed, protobuf`: each record prefixed with 4-byte
  ///   big-endian length.
  ///
  /// For the text-input path (when [textPrompt] is supplied), system messages
  /// and the user prompt are CLI-constructed, so they are encoded and written
  /// as structured records — the relay law governs user-supplied pipe content
  /// only. For typed input ([typedStdin] supplied), system messages are encoded
  /// in [inputEncoding] and prepended; user bytes from [typedStdin] are relayed
  /// verbatim, never decoded.
  ///
  /// [out] and [typedStdin] are injectable for testing.
  Future<void> relayTurn({
    required ChatIOConfig config,
    required String inputEncoding,
    required String outputEncoding,
    String? textPrompt,
    Stream<List<int>>? typedStdin,
    List<ChatMessage> systemMessages = const [],
    IOSink? out,
    StringSink? errOut,
    bool verbose = false,
  }) async {
    assert(
      (textPrompt != null) != (typedStdin != null),
      'exactly one of textPrompt or typedStdin must be provided',
    );
    out ??= stdout;
    errOut ??= stderr;

    // For text input we force structured so system+user messages are written
    // as typed records (unstructured mode can't carry system role separately).
    final isTextInput = textPrompt != null;
    final effectiveConfig = isTextInput
        ? config.copyWith(
            inputFormat: Format.structured,
            inputEncoding: Encoding.protobuf,
          )
        : config;

    final fd = await _bentos.open(devicePath);
    try {
      for (final (cmd, payload) in configToIoctls(effectiveConfig)) {
        await _bentos.ioctl(fd, cmd, payload);
      }

      final resolvedPrompt = textPrompt;
      final resolvedStdin = typedStdin;
      if (resolvedPrompt != null) {
        for (final m in systemMessages) {
          await _bentos.write(fd, encodeMessage(m));
        }
        await _bentos.write(fd, encodeMessage(ChatMessage.userText(resolvedPrompt)));
      } else if (resolvedStdin != null) {
        // Typed input: system messages in the correct encoding, then raw stdin.
        for (final m in systemMessages) {
          final bytes = inputEncoding == 'json'
              ? Uint8List.fromList(utf8.encode(encodeMessageJson(m)))
              : encodeMessage(m);
          await _bentos.write(fd, bytes);
        }
        await _relayInput(resolvedStdin, inputEncoding, fd);
      }

      // Output: relay raw bytes from device with appropriate framing.
      final isTypedOutput = config.outputFormat == Format.structured;
      while (true) {
        final raw = await _bentos.read(fd);
        if (raw.isEmpty) break;
        if (!isTypedOutput) {
          out.add(raw);
        } else if (outputEncoding == 'json') {
          out.add(raw);
          out.add(const [10]); // '\n' — record framing for json
        } else {
          // protobuf: 4-byte big-endian length-prefix + payload
          final frame = Uint8List(4 + raw.length);
          ByteData.sublistView(frame).setUint32(0, raw.length);
          frame.setRange(4, 4 + raw.length, raw);
          out.add(frame);
        }
      }
    } finally {
      await _bentos.close(fd);
    }
  }

  /// Relay raw bytes from [src] to the open fd: json = split on `\n` and
  /// write each line's bytes; protobuf = read 4-byte big-endian
  /// length-prefix frames and write each payload.
  Future<void> _relayInput(
    Stream<List<int>> src,
    String inputEncoding,
    int fd,
  ) async {
    if (inputEncoding == 'json') {
      await for (final line in src.transform(utf8.decoder).transform(LineSplitter())) {
        if (line.trim().isEmpty) continue;
        await _bentos.write(fd, Uint8List.fromList(utf8.encode(line)));
      }
    } else {
      // protobuf: buffer all, then slice length-prefix frames
      final all = await src.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      var offset = 0;
      while (offset + 4 <= all.length) {
        final len = ByteData.sublistView(
          Uint8List.fromList(all.sublist(offset, offset + 4)),
        ).getUint32(0);
        offset += 4;
        if (offset + len <= all.length) {
          await _bentos.write(
            fd,
            Uint8List.fromList(all.sublist(offset, offset + len)),
          );
          offset += len;
        }
      }
    }
  }
}
