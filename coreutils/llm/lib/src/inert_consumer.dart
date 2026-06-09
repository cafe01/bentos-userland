/// The inert consumer — the shared core both `prompt` and `chat` are built on.
///
/// It embodies the coreutil's whole ontology (`llm` spec §1): it opens
/// `/dev/llm/<vendor>/<model>` via the boot layer and streams `infer`, never
/// touching keys, vendors, or drivers. The device is booted ONCE and reused
/// across turns — `chat` does not re-boot per turn.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';

/// A booted, reusable handle on one `/dev/llm/*` device.
class InertConsumer {
  final BentosChatDevice _device;

  InertConsumer(this._device);

  /// Boots the in-process portal for [devicePath] once and returns a consumer
  /// over it. Throws [LlmBootException] if the path cannot be routed (malformed
  /// path / unknown vendor) — a missing credential is NOT raised here; it fails
  /// the later turn's `open` with EACCES (a [BentosException]).
  factory InertConsumer.forDevice(String devicePath) =>
      InertConsumer(BentosChatDevice(bootLlmDevice(devicePath), devicePath));

  String get devicePath => _device.devicePath;

  /// Streams one inference cycle over the open device: writes each `TextDelta`
  /// (or `Block` with `TextContent` when streaming is off) to stdout, optionally
  /// prints `Complete` metadata to stderr ([verbose]), and returns the
  /// assistant's full text — so a caller holding a conversation can append it
  /// and carry context forward.
  ///
  /// [systemMessages] are prepended before [messages] (system role first).
  /// [config] carries `maxTokens` / `temperature` / `streaming` ioctls; defaults
  /// are fine.
  ///
  /// A `BentosException` (e.g. EACCES with no credential) propagates to the
  /// caller, surfaced exactly as a POSIX/IO error from behind the device.
  Future<String> streamTurn(
    List<ChatMessage> messages, {
    List<ChatMessage> systemMessages = const [],
    ChatIOConfig config = const ChatIOConfig(),
    bool verbose = false,
  }) async {
    final reply = StringBuffer();
    final wire = [...systemMessages, ...messages];
    await for (final event in _device.infer(wire, config)) {
      switch (event) {
        case TextDelta(:final text):
          stdout.write(text);
          reply.write(text);
        // When streaming=false the driver emits Block events instead of triads.
        case Block(:final content) when content is TextContent:
          stdout.write(content.text);
          reply.write(content.text);
        case Complete(:final metadata):
          stdout.writeln();
          if (verbose) {
            stderr.writeln(
              '[${metadata.model} · ${metadata.stopReason} · '
              '${metadata.usage?.inputTokens}in/'
              '${metadata.usage?.outputTokens}out]',
            );
          }
        default:
          break; // thinking / function events: not surfaced by the casual register.
      }
    }
    return reply.toString();
  }

  /// Runs one inference cycle in the scriptable register: folds all events into
  /// a single assembled [ChatMessage] (via [foldToMessage]) and writes it as one
  /// proto3 JSON line to [out] (defaults to stdout). Returns the assembled
  /// message so the caller can use it (e.g. append to a conversation in memory).
  ///
  /// [systemMessages] are prepended before [messages] (system role first).
  /// Handles heterogeneous messages (TextContent + FunctionCallContent in the
  /// same assistant turn) because [foldToMessage] accumulates all block types.
  ///
  /// [out] and [errOut] are injectable for testing; production defaults to the
  /// real stdout/stderr.
  Future<ChatMessage> filterTurn(
    List<ChatMessage> messages, {
    List<ChatMessage> systemMessages = const [],
    ChatIOConfig config = const ChatIOConfig(),
    bool verbose = false,
    StringSink? out,
    StringSink? errOut,
  }) async {
    out ??= stdout;
    errOut ??= stderr;

    // Tap the Complete event for verbose metadata without consuming the stream
    // twice — the map transformer runs synchronously as events flow through, so
    // metadata is set before foldToMessage's future resolves.
    ChatMetadata? metadata;
    final wire = [...systemMessages, ...messages];
    final tapped = _device.infer(wire, config).map((event) {
      if (event is Complete) metadata = event.metadata;
      return event;
    });

    final message = await tapped.foldToMessage();
    out.writeln(encodeMessageJson(message));

    if (verbose && metadata != null) {
      errOut.writeln(
        '[${metadata!.model} · ${metadata!.stopReason} · '
        '${metadata!.usage?.inputTokens}in/'
        '${metadata!.usage?.outputTokens}out]',
      );
    }
    return message;
  }
}
