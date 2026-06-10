/// `chatbot show [session] [--json]` — print a session transcript.
///
/// Minimal dump only: decode the tx record and print it. A real renderer —
/// roles, colors, tool-call folding, token meters — is the `chat-render`
/// coreutil (the projection family's `map`), which does NOT exist yet. This is
/// a placeholder until `chat-render` lands as the rightful owner.
///
/// No arg: the current session. With a sid: `tx switch` to it first (this DOES
/// move the current ref — selecting a session to read is selecting it; full
/// cross-session read without switching is again `chat-render`'s job).
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat/chat.dart';
import 'package:tx/tx.dart';

import '../session_resolve.dart';

class ShowCommand extends Command<int> {
  ShowCommand() {
    argParser
      ..addOption(
        'agent',
        abbr: 'a',
        help: 'The being whose session to show (default: \$BENTOS_AGENT).',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit raw JSONL (one proto3-JSON ChatMessage per line).',
      );
  }

  @override
  String get name => 'show';

  @override
  String get description => 'Print a session transcript.';

  @override
  String get invocation => 'chatbot show [<session>] [--json]';

  @override
  Future<int> run() async {
    final TxRepo repo;
    try {
      repo = openRepoForAgent(argResults!['agent'] as String?);
    } on TxResolveError catch (e) {
      stderr.writeln('chatbot: $e');
      return 1;
    }
    if (!repo.hasSession) {
      stderr.writeln('chatbot: no sessions found.');
      return 1;
    }

    final sid = argResults!.rest.firstOrNull;
    if (sid != null) {
      try {
        await repo.switchTo(sid);
      } on TxNoSessionError catch (e) {
        stderr.writeln('chatbot: $e');
        return 1;
      }
    }

    final messages = ChatSession(repo).history();

    if (argResults!['json'] as bool) {
      for (final m in messages) {
        stdout.writeln(encodeMessageJson(m));
      }
      return 0;
    }

    for (final m in messages) {
      final role = switch (m.role) {
        ChatRole.user => 'You',
        ChatRole.assistant => 'Assistant',
        ChatRole.system => 'System',
      };
      final text =
          m.content.whereType<TextContent>().map((c) => c.text).join();
      stdout.writeln('[$role] $text');
    }
    return 0;
  }
}
