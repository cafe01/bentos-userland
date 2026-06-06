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
      await _applyConfig(fd, config);
      for (final m in messages) {
        await _bentos.write(fd, encodeMessage(m));
      }
      while (true) {
        // The first read() triggers inference; each frame is one ChatEvent.
        final frame = await _bentos.read(fd);
        if (frame.isEmpty) return; // EOF — driver closed the stream.
        final event = decodeEvent(frame);
        yield event;
        if (event is Complete) return;
      }
    } finally {
      await _bentos.close(fd);
    }
  }

  /// Translates non-default [config] fields into their `CHAT_SET_*` ioctls.
  ///
  /// SEAM (D3): the per-command payload encodings belong to the subsystem's
  /// ioctl ConfigCodec, built with the first driver. Until it lands, only the
  /// all-default config is expressible through this binding.
  Future<void> _applyConfig(int fd, ChatIOConfig config) async {
    if (config == const ChatIOConfig()) return;
    throw UnsupportedError(
      'CHAT_SET_* payload encodings land with the subsystem ConfigCodec (D3); '
      'only the default ChatIOConfig is expressible until then',
    );
  }
}
