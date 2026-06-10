/// `ChatbotRunner` — the coreutil's command runner.
///
/// Mirrors `LlmRunner` from `coreutils/llm/`. Registers commands, owns
/// --version, maps UsageException to exit 64.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../version.dart';
import 'commands/chat_command.dart';
import 'commands/list_command.dart';
import 'commands/resume_command.dart';
import 'commands/show_command.dart';

/// Routes bare `chatbot "prompt"` and bare `chatbot` to the `chat` command.
///
/// - Empty args → `['chat']` (REPL mode).
/// - Flags-only (e.g. `--version`) → unchanged (runner handles them first).
/// - Positional arg that is not a known command → prepend 'chat' (single-shot).
/// - Known command name → unchanged (explicit subcommand).
List<String> withDefaultCommand(List<String> args, Set<String> knownCommands) {
  if (args.isEmpty) return ['chat'];
  final firstNonFlag =
      args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');
  if (firstNonFlag.isEmpty) return args;
  if (knownCommands.contains(firstNonFlag)) return args;
  return ['chat', ...args];
}

class ChatbotRunner extends CommandRunner<int> {
  ChatbotRunner()
      : super(
          'chatbot',
          'chatbot.exe — LUCA with species ontology. '
              'The first agent built on the SDK.',
        ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print version and exit.',
    );
    addCommand(ChatCommand());
    addCommand(ResumeCommand());
    addCommand(ListCommand());
    addCommand(ShowCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(
        withDefaultCommand(args.toList(), commands.keys.toSet()),
      );
      if (results['version'] == true) {
        stdout.writeln('chatbot $chatbotVersion');
        return 0;
      }
      return await runCommand(results) ?? 0;
    } on UsageException catch (e) {
      stderr.writeln(e);
      return 64; // EX_USAGE
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command == null) {
      printUsage();
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}
