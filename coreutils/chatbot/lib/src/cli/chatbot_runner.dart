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
import 'commands/resume_command.dart';

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
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args.toList());
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
