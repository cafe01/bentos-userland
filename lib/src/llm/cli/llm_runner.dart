/// `LlmRunner` — the coreutil's command runner.
///
/// Registers the commands, owns `--version`, routes bare `llm "prompt…"` to the
/// default command, and maps a top-level [UsageException] to exit 64 (EX_USAGE).
/// Mirrors `bentos_agent`'s `AgentRunner`.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../version.dart';
import 'commands/chat_command.dart';
import 'commands/config_command.dart';
import 'commands/models_command.dart';
import 'commands/prompt_command.dart';
import 'default_command.dart';

class LlmRunner extends CommandRunner<int> {
  LlmRunner()
      : super(
          'llm',
          'The inert inference coreutil — opens /dev/llm/<vendor>/<model> '
              'and streams the answer.',
        ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print version and exit.',
    );
    addCommand(PromptCommand());
    addCommand(ChatCommand());
    addCommand(ConfigCommand());
    addCommand(ModelsCommand());
  }

  /// [stdinHasPrompt] is true when the process's stdin is piped (not a TTY), so
  /// a bare `echo … | llm` routes to the prompt command instead of showing
  /// usage. The entrypoint supplies it; it defaults to false so tests that
  /// drive the runner directly are unaffected.
  @override
  Future<int> run(Iterable<String> args, {bool stdinHasPrompt = false}) async {
    try {
      final results = parse(
        withDefaultCommand(
          args.toList(),
          commands.keys.toSet(),
          stdinHasPrompt: stdinHasPrompt,
        ),
      );
      if (results['version'] == true) {
        stdout.writeln('llm $llmVersion');
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
