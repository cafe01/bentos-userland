import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:tx/tx.dart';

import '../session_resolve.dart';

/// Shared base for chatbot subcommands that open a device and infer.
///
/// Holds the common flags and the entity → tx repo resolution.
abstract class ChatbotBaseCommand extends Command<int> {
  ChatbotBaseCommand() {
    argParser
      ..addOption(
        'agent',
        abbr: 'a',
        help: 'The being whose session to use (default: \$BENTOS_AGENT).',
      )
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

  /// The entity's tx repo (`--agent ?? $BENTOS_AGENT`, rooted at the place).
  TxRepo openRepo() => openRepoForAgent(argResults!['agent'] as String?);

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
