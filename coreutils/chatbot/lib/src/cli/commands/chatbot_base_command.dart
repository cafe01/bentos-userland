import 'package:args/command_runner.dart';

/// Shared base for all chatbot subcommands.
///
/// Holds the --device flag and the device boot logic that all commands need.
/// TODO(chatbot-design.md §6): wire ChatbotBrain + ChatDevice boot here once
/// the brain layer lands.
abstract class ChatbotBaseCommand extends Command<int> {
  ChatbotBaseCommand() {
    argParser.addOption(
      'device',
      abbr: 'd',
      help: 'LLM device path or alias (e.g. /dev/llm/openai/gpt-4o-mini).',
    );
  }
}
