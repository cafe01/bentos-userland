import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chat_inference/chat_inference.dart';

/// Shared base for all chatbot subcommands.
///
/// Holds the flags common to commands that open a device and infer.
abstract class ChatbotBaseCommand extends Command<int> {
  ChatbotBaseCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'LLM device path or alias (e.g. openai/gpt-4o-mini).',
      )
      ..addMultiOption(
        'system',
        abbr: 's',
        help: 'System prompt. Repeatable — segments joined in order.',
        valueHelp: 'text',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print Complete metadata (model · stopReason · usage) to stderr.',
      );
  }

  bool get verbose => argResults!['verbose'] as bool;

  List<ChatMessage> get systemMessages {
    final segments = argResults!['system'] as List<String>;
    if (segments.isEmpty) return const [];
    return [ChatMessage.systemText(segments.join('\n'))];
  }

  /// Resolves the device path: --device flag → BENTOS_LLM_DEVICE env → default.
  String resolveDevicePath() {
    final explicit = argResults!['device'] as String?;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.startsWith('/') ? explicit : '/dev/llm/$explicit';
    }
    final fromEnv = Platform.environment['BENTOS_LLM_DEVICE'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv.startsWith('/') ? fromEnv : '/dev/llm/$fromEnv';
    }
    return '/dev/llm/openai/gpt-4o-mini';
  }
}
