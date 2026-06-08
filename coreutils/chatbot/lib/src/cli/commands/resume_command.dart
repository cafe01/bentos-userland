import 'chatbot_base_command.dart';

/// `chatbot resume` — resume a previous session from the transaction log.
///
/// TODO(chatbot-design.md §5 + agent-sdk-design.md §1): implement at v0.2
/// once TxLog lands. Steps:
///   1. Resolve session id (latest or `--session &lt;id&gt;`).
///   2. Reconstruct AgentCtx from TxLog.history().
///   3. Hand off to the REPL loop with the restored context (AgentCtx).
class ResumeCommand extends ChatbotBaseCommand {
  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a previous conversation (v0.2+).';

  @override
  Future<int> run() async {
    // TODO: implement — see class doc above.
    throw UnimplementedError('chatbot resume — not yet implemented (v0.2)');
  }
}
