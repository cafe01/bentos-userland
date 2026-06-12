// OpenAI driver — conformance suite, run at the AGGREGATOR (userland).
//
// The cycle break (S441 turn 2): conformance runs HERE, where the InProcessBentos
// harness + the driver-agnostic suite both live, with the driver as a userland
// dev_dependency. The driver package itself no longer references bentos_userland.
//
// Proves the OpenAI driver honors the ChatInference contract by running the
// subsystem's driver-agnostic suite against it (fake/CI mode, keyless). The
// suite decides what is tested; this file only wires the driver to the harness.
//
// NOTE: this harness binds the driver DIRECTLY (openaiChatDriver in fake mode)
// rather than via registerBundledLlmDrivers/bootLlmDevice — it needs the fake
// gate + error/parallel flags, which the production registry path deliberately
// does not expose. The bundled-registry path is exercised by boot_test.dart.

import 'dart:async';
import 'dart:typed_data';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat_inference/conformance.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';
import 'package:stream_channel/stream_channel.dart';

void main() {
  registerConformanceSuite(OpenAIConformanceHarness());
}

/// Wires the OpenAI driver (fake mode) into the conformance harness.
class OpenAIConformanceHarness implements ChatDriverHarness {
  @override
  String get defaultModel => 'gpt-4o';

  @override
  bool get supportsFunctionCalls => true;

  @override
  bool get supportsReasoningBudget => false;

  @override
  String devicePath(String model) => '/dev/llm/openai/$model';

  // One bound driver + bentos serves the infer()-level and readiness groups;
  // each open() is a fresh session on the same channel.
  late final Bentos _bentos = _bind(model: defaultModel);

  @override
  ChatDevice device(String model) =>
      BentosChatDevice(_bentos, devicePath(model));

  @override
  ChatSyscalls get syscalls => _BentosSyscalls(_bentos);

  @override
  GatedSession gatedSession(String model) {
    final gate = Completer<void>();
    final bentos = _bind(model: model, gate: gate.future);
    return GatedSession(_BentosSyscalls(bentos), () => gate.complete());
  }

  @override
  ChatDevice erroringDevice(String model) {
    final bentos = _bind(model: model, errorBeforeFrame: true);
    return BentosChatDevice(bentos, devicePath(model));
  }

  @override
  ChatDevice midStreamErroringDevice(String model) {
    final bentos = _bind(model: model, errorMidFrame: true);
    return BentosChatDevice(bentos, devicePath(model));
  }

  @override
  ChatDevice parallelFunctionCallDevice(String model) {
    final bentos = _bind(model: model, parallelCalls: true);
    return BentosChatDevice(bentos, devicePath(model));
  }

  @override
  ChatErrno? errnoOf(Object error) {
    if (error is! BentosException) return null;
    return switch (error.errno) {
      BentosErrno.enotsup => ChatErrno.notSupported,
      BentosErrno.einval => ChatErrno.invalidArgument,
      BentosErrno.eio => ChatErrno.io,
      BentosErrno.ebadf => ChatErrno.badFd,
      BentosErrno.enoent => ChatErrno.notFound,
      BentosErrno.eacces => ChatErrno.accessDenied,
    };
  }

  Bentos _bind(
      {required String model,
      Future<void>? gate,
      bool errorBeforeFrame = false,
      bool errorMidFrame = false,
      bool parallelCalls = false}) {
    final driver = openaiChatDriver(
        model: model,
        apiKey: 'fake',
        fakeFirstFrameGate: gate,
        fakeErrorBeforeFrame: errorBeforeFrame,
        fakeErrorMidFrame: errorMidFrame,
        fakeParallelCalls: parallelCalls);
    final pair = StreamChannelController<Uint8List>();
    driver.serveChannel(pair.foreign);
    return InProcessBentos(capMap: {'/dev/llm/': pair.local});
  }
}

/// Adapts the userland [Bentos] surface to the suite's narrowed [ChatSyscalls]
/// port — a thin pass-through; Bentos already has exactly these calls.
class _BentosSyscalls implements ChatSyscalls {
  final Bentos _b;
  _BentosSyscalls(this._b);

  @override
  Future<int> open(String path) => _b.open(path);

  @override
  Future<void> ioctl(int fd, int cmd, Uint8List payload) =>
      _b.ioctl(fd, cmd, payload);

  @override
  Future<void> write(int fd, Uint8List frame) => _b.write(fd, frame);

  @override
  Future<void> fsync(int fd) => _b.fsync(fd);

  @override
  Future<bool> poll(int fd) => _b.poll(fd);

  @override
  Future<Uint8List> read(int fd) => _b.read(fd);

  @override
  Future<void> close(int fd) => _b.close(fd);
}
