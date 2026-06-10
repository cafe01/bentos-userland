/// `chatbot list` — list the entity's sessions (via `tx ls`).
///
/// Sessions are tx branches: sids, current marked with `*`. The richer
/// listing the old SessionStore offered (createdAt, turn counts, human names)
/// is DELIBERATELY degraded here — that metadata is the projection family's
/// altitude (`stats` is the future owner, reading the log; `tx` stays
/// content-blind). Named/aliased sessions are a future tx feature (an alias /
/// symlink over the sid — Cafe's design, not decided here).
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:tx/tx.dart';

import '../session_resolve.dart';

class ListCommand extends Command<int> {
  ListCommand() {
    argParser.addOption(
      'agent',
      abbr: 'a',
      help: 'The being whose sessions to list (default: \$BENTOS_AGENT).',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List all sessions.';

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
      stdout.writeln('No sessions.');
      return 0;
    }
    final current = await repo.current();
    for (final sid in await repo.ls()) {
      stdout.writeln('${sid == current ? '* ' : '  '}$sid');
    }
    return 0;
  }
}
