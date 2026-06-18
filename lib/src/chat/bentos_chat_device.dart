import 'dart:typed_data';

import 'package:chat_inference/chat_inference.dart';

import '../bentos.dart';
import 'chat_ioctl_cmds.dart';

/// [ChatDevice] over the [Bentos] syscall surface — the stdlib's `sys/chat.h`
/// binding, client-SDK sugar over the device's real surface
/// (`chatinference-subsystem.md` §"The infer() sugar"):
///
/// 1. `open(devicePath)` — one session per inference cycle;
/// 2. config fields → their `CHAT_SET_*` ioctls;
/// 3. `messages.forEach(write)` — one RAW message per `write()`;
/// 4. the first `read()` triggers inference; each `read()` returns one RAW
///    event payload, yielded until [Complete];
/// 5. `close()`.
///
/// The wire is RAW (t-305): the datagram boundary IS the I/O syscall — one
/// write = one message record, one read = one event. No length-prefix; the
/// framework (bentos_driver_sdk, t-306) preserves each boundary end to end.
/// Payloads cross as canonical protobuf via the subsystem codec
/// (`chat_inference`'s `encodeMessage`/`decodeEvent`) — opaque to the kernel,
/// typed at both ends.
class BentosChatDevice implements ChatDevice {
  final Bentos _bentos;

  @override
  final String devicePath;

  BentosChatDevice(this._bentos, this.devicePath);

  @override
  Future<ChatCapabilities> get capabilities async {
    final fd = await _bentos.open(devicePath, mode: OpenMode.readOnly);
    try {
      return decodeCapabilities(
        await _bentos.ioctl(fd, chatGetInfo, Uint8List(0)),
      );
    } finally {
      await _bentos.close(fd);
    }
  }

  @override
  Stream<ChatEvent> infer(
    List<ChatMessage> messages, [
    ChatIOConfig config = const ChatIOConfig(),
  ]) async* {
    final fd = await _bentos.open(devicePath);
    try {
      // infer() is the full-fidelity, typed sugar: it speaks structured BOTH
      // ways — writes RAW encodeMessage() records in, decodes RAW ChatEvent
      // records out. Override both formats so the base decodes proto records
      // (not raw text) and encodes proto events (not lossy UTF-8 text).
      await _applyConfig(fd, config.copyWith(
        inputFormat: Format.structured,
        outputFormat: Format.structured,
      ));
      for (final m in messages) {
        await _bentos.write(fd, encodeMessage(m));
      }
      while (true) {
        // Each read() returns one RAW ChatEvent payload — the framework
        // preserves the per-event boundary the driver yielded (t-305/t-306).
        final raw = await _bentos.read(fd);
        if (raw.isEmpty) return; // EOF — driver closed the stream.
        final event = decodeEvent(raw);
        yield event;
        if (event is Complete) return;
      }
    } finally {
      await _bentos.close(fd);
    }
  }

  /// Translates non-default [config] fields into their `CHAT_SET_*` ioctls
  /// via the subsystem ConfigCodec.
  Future<void> _applyConfig(int fd, ChatIOConfig config) async {
    for (final (cmd, payload) in configToIoctls(config)) {
      await _bentos.ioctl(fd, cmd, payload);
    }
  }
}
