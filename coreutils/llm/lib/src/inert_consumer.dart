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
  /// to stdout, optionally prints `Complete` metadata to stderr ([verbose]),
  /// and returns the assistant's full text — so a caller holding a conversation
  /// can append it and carry context forward.
  ///
  /// A `BentosException` (e.g. EACCES with no credential) propagates to the
  /// caller, surfaced exactly as a POSIX/IO error from behind the device.
  Future<String> streamTurn(
    List<ChatMessage> messages, {
    bool verbose = false,
  }) async {
    final reply = StringBuffer();
    await for (final event in _device.infer(messages)) {
      switch (event) {
        case TextDelta(:final text):
          stdout.write(text);
          reply.write(text);
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
          break; // thinking / function events: not surfaced by this coreutil.
      }
    }
    return reply.toString();
  }
}
