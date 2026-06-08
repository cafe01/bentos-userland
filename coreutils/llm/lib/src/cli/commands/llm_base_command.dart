/// Shared base for the `llm` commands: the flags and the device-boot step both
/// `prompt` and `chat` need, so neither re-implements them.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/boot.dart';

import '../../config.dart';
import '../../device.dart';
import '../../inert_consumer.dart';

/// Base for any command that opens a `/dev/llm/*` device. Registers the common
/// `--device` / `--verbose` flags and resolves the inert consumer once.
abstract class LlmBaseCommand extends Command<int> {
  LlmBaseCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device path /dev/llm/<vendor>/<model> '
            '(overrides $deviceEnvVar and the default).',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print Complete metadata (model · stopReason · usage) to stderr.',
      );
  }

  bool get verbose => argResults!['verbose'] as bool;

  /// Resolves the device path (`--device` / env / default) and boots the inert
  /// consumer once. On a routing failure ([LlmBootException]) reports to stderr
  /// and returns null — the caller returns exit 3. A missing credential is NOT
  /// a boot error: it fails the first turn's `open` with EACCES.
  InertConsumer? bootConsumer() {
    final devicePath = resolveDevicePath(
      argResults!['device'] as String?,
      environment: Platform.environment,
    );
    try {
      return InertConsumer.forDevice(devicePath);
    } on LlmBootException catch (e) {
      stderr.writeln('llm: $e');
      return null;
    }
  }
}
