/// `chatbot show <session> [--json]` — print a session transcript.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';

import '../../session/session_store.dart';

class ShowCommand extends Command<int> {
  ShowCommand() {
    argParser.addFlag(
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
  String get invocation => 'chatbot show <session> [--json]';

  @override
  Future<int> run() async {
    final args = argResults!.rest;
    if (args.isEmpty) {
      stderr.writeln('chatbot show: session ID or name required.');
      usageException('session ID or name required');
    }
    final store = SessionStore.open();
    final idOrName = args.first;
    final messages = store.load(idOrName);
    if (messages == null) {
      stderr.writeln('chatbot: session not found: $idOrName');
      return 1;
    }

    final asJson = argResults!['json'] as bool;
    if (asJson) {
      for (final m in messages) {
        stdout.writeln(encodeMessageJson(m));
      }
      return 0;
    }

    // Human-readable transcript.
    for (final m in messages) {
      final role = switch (m.role) {
        ChatRole.user => 'You',
        ChatRole.assistant => 'Assistant',
        ChatRole.system => 'System',
      };
      final text = m.content
          .whereType<TextContent>()
          .map((c) => c.text)
          .join();
      stdout.writeln('[$role] $text');
    }
    return 0;
  }
}
