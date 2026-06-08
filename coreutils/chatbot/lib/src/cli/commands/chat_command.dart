import 'chatbot_base_command.dart';

/// `chatbot chat` — interactive multi-turn REPL.
///
/// TODO(chatbot-design.md §6): implement the REPL loop:
///   1. Boot ChatDevice via device path resolution.
///   2. Instantiate ChatbotBrain (AgentBrain + AgentCpu).
///   3. Loop: read line → UserPromptEvent → brain.processStimulus → stream
///      reactions → stdout. /exit or Ctrl-D breaks.
///   4. (v0.2) Store hook: append each reaction to TxLog if one is injected.
class ChatCommand extends ChatbotBaseCommand {
  @override
  String get name => 'chat';

  @override
  String get description => 'Start an interactive multi-turn conversation.';

  @override
  Future<int> run() async {
    // TODO: implement — see class doc above.
    throw UnimplementedError('chatbot chat — not yet implemented');
  }
}
