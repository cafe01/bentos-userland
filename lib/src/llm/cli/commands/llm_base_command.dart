/// Shared base for the `llm` commands: the flags and the device-boot step both
/// `prompt` and `chat` need, so neither re-implements them.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/boot.dart';
import 'package:chat_inference/chat_inference.dart';

import '../../config.dart';
import '../../device.dart';
import '../../inert_consumer.dart';
import '../../llm_config.dart';

/// Base for any command that opens a `/dev/llm/*` device. Registers the common
/// flags and resolves the inert consumer once.
abstract class LlmBaseCommand extends Command<int> {
  LlmBaseCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device path /dev/llm/<vendor>/<model> '
            '(overrides $deviceEnvVar and the default).',
      )
      ..addMultiOption(
        'system',
        abbr: 's',
        help: 'System prompt. Repeatable — segments are joined in order.',
        valueHelp: 'text',
      )
      ..addOption(
        'max-tokens',
        abbr: 't',
        help: 'Cap the generated length.',
        valueHelp: 'n',
      )
      ..addOption(
        'temperature',
        help: 'Sampling temperature (0.0–1.0).',
        valueHelp: '0.0–1.0',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print Complete metadata (model · stopReason · usage) to stderr.',
      );
  }

  bool get verbose => argResults!['verbose'] as bool;

  /// System messages built from the `-s` segments (joined in order into one
  /// system message). Empty when the flag was not provided.
  List<ChatMessage> get systemMessages {
    final segments = argResults!['system'] as List<String>;
    if (segments.isEmpty) return const [];
    return [ChatMessage.systemText(segments.join('\n'))];
  }

  /// The `ChatIOConfig` built from `--max-tokens` and `--temperature`. Fields
  /// that were not passed remain null (driver default).
  ChatIOConfig get ioConfig {
    final maxTokensStr = argResults!['max-tokens'] as String?;
    final temperatureStr = argResults!['temperature'] as String?;
    final maxTokens =
        maxTokensStr != null ? int.tryParse(maxTokensStr) : null;
    final temperature =
        temperatureStr != null ? double.tryParse(temperatureStr) : null;
    return ChatIOConfig(maxTokens: maxTokens, temperature: temperature);
  }

  /// Resolves the device path (`--device` incl. alias / env / configured
  /// default / built-in) and boots the inert consumer once.
  ///
  /// On a routing failure ([LlmBootException]) reports to stderr and returns
  /// null — the caller returns exit 3. A missing credential is NOT a boot
  /// error: it fails the first turn's `open` with EACCES.
  Future<InertConsumer?> bootConsumer() async {
    final config = LlmConfig.load();
    final devicePath = resolveDevicePath(
      argResults!['device'] as String?,
      environment: Platform.environment,
      config: config,
    );
    try {
      return InertConsumer.forDevice(devicePath);
    } on LlmBootException catch (e) {
      stderr.writeln('llm: $e');
      return null;
    }
  }
}
