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
/// 3. `messages.forEach(write)` — one message frame per `write()`;
/// 4. the first `read()` triggers inference; each frame decodes to one
///    [ChatEvent], yielded raw until [Complete];
/// 5. `close()`.
///
/// Frames cross the boundary as canonical protobuf via the subsystem codec
/// (`chat_inference`'s `encodeMessage`/`decodeEvent`) — opaque payload to the
/// kernel, typed at both ends.
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
      // infer() always writes encodeMessage() frames (structured format).
      // Override inputFormat so the driver decodes proto frames, not raw text.
      await _applyConfig(fd, config.copyWith(inputFormat: Format.structured));
      for (final m in messages) {
        await _bentos.write(fd, encodeMessageFrame(m));
      }
      while (true) {
        // The first read() returns one or more length-prefixed ChatEvent frames
        // ([4-byte size][payload] per event — structured output spec §output-modes).
        final raw = await _bentos.read(fd);
        if (raw.isEmpty) return; // EOF — driver closed the stream.
        for (final event in decodeEventFrames(raw)) {
          yield event;
          if (event is Complete) return;
        }
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
