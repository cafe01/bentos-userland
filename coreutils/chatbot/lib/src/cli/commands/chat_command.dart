/// `chatbot` default command — single-shot and interactive REPL.
///
/// `chatbot "prompt"` runs one turn; bare `chatbot` loops (the species `while`).
/// Either way the conversation is one continuous line in the entity's tx
/// session: every turn reads the ambient context (`tx cat`) and appends each
/// mutation (`tx append`). There is no bespoke session store — persistence is
/// the same tx substrate every userland program shares.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat/chat.dart';
import 'package:tx/tx.dart';

import '../repl.dart';
import 'chatbot_base_command.dart';

class ChatCommand extends ChatbotBaseCommand {
  ChatCommand() {
    argParser.addOption(
      'tools',
      abbr: 't',
      help: 'Directory of tool executables and *.json FunctionDefinition files.',
      valueHelp: 'dir',
    );
  }

  @override
  String get name => 'chat';

  @override
  String get description =>
      'Start or continue a conversation (default command).';

  @override
  String get invocation =>
      'chatbot [-a <agent>] [-d <device>] [-s <system>]... [-t <tools>] [-v] [<prompt>]';

  @override
  Future<int> run() async {
    // Resolve the being and open its ambient session on demand.
    final TxRepo repo;
    try {
      repo = openRepo();
    } on TxResolveError catch (e) {
      stderr.writeln('chatbot: $e');
      return 1;
    }
    final session = ChatSession(repo);
    try {
      await session.ensureOpen();
    } on TxGitError catch (e) {
      stderr.writeln('chatbot: $e');
      return 2;
    }

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

    final conversation = [...session.history()];
    final positional = argResults!.rest;

    if (positional.isNotEmpty) {
      final userMsg = ChatMessage.userText(positional.join(' '));
      await session.record(userMsg); // write-ahead
      conversation.add(userMsg);
      try {
        await turn.run(conversation);
        return 0;
      } on BentosException catch (e) {
        stderr.writeln('chatbot: $e');
        return 1;
      }
    }

    final code = await runRepl(
      session: session,
      turn: turn,
      conversation: conversation,
    );
    stderr.writeln('Session ${await repo.current()} sealed.');
    return code;
  }
}
