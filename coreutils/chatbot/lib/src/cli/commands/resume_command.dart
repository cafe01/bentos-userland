/// `chatbot resume [session]` — reopen a session and continue it.
///
/// No arg: continue the CURRENT tx session (the HEAD is the latest active line
/// — cleaner than the old `latestId`). With a sid: `tx switch` to it first.
/// Either way the conversation is rebuilt from the tx log, not memory.
library;

import 'dart:io';

import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat/chat.dart';
import 'package:tx/tx.dart';

import '../repl.dart';
import 'chatbot_base_command.dart';

class ResumeCommand extends ChatbotBaseCommand {
  ResumeCommand() {
    argParser.addOption(
      'tools',
      abbr: 't',
      help: 'Directory of tool executables and *.json FunctionDefinition files.',
      valueHelp: 'dir',
    );
  }

  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a previous conversation.';

  @override
  String get invocation => 'chatbot resume [<session>]';

  @override
  Future<int> run() async {
    final TxRepo repo;
    try {
      repo = openRepo();
    } on TxResolveError catch (e) {
      stderr.writeln('chatbot: $e');
      return 1;
    }
    if (!repo.hasSession) {
      stderr.writeln('chatbot: no sessions found.');
      return 1;
    }

    // With a sid, switch the current ref to it; without, continue current.
    final sid = argResults!.rest.firstOrNull;
    if (sid != null) {
      try {
        await repo.switchTo(sid);
      } on TxNoSessionError catch (e) {
        stderr.writeln('chatbot: $e');
        return 1;
      }
    }

    final session = ChatSession(repo);
    final conversation = [...session.history()];
    stderr.writeln(
      'Resuming session ${await repo.current()} '
      '(${conversation.length} messages).',
    );

    final devicePath = resolveDevicePath();
    final BentosChatDevice device;
    try {
      device = BentosChatDevice(bootLlmDevice(devicePath), devicePath);
    } on LlmBootException catch (e) {
      stderr.writeln('chatbot: $e');
      return 3;
    }

    final toolsDir = argResults!['tools'] as String?;
    final tools = [
      ...builtinTools(),
      if (toolsDir != null) ...loadTools(toolsDir),
    ];
    final turn = Turn(
      device: device,
      systemMessages: systemMessages,
      config: ChatIOConfig(functions: tools.isEmpty ? null : tools),
      toolsDir: toolsDir,
      verbose: verbose,
      persist: session.record,
    );

    final code = await runRepl(
      session: session,
      turn: turn,
      conversation: conversation,
    );
    stderr.writeln('Session ${await repo.current()} sealed.');
    return code;
  }
}
