/// `chatbot list` — list all sessions.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../session/session_store.dart';

class ListCommand extends Command<int> {
  @override
  String get name => 'list';

  @override
  String get description => 'List all sessions.';

  @override
  Future<int> run() async {
    final sessions = SessionStore.open().list();
    if (sessions.isEmpty) {
      stdout.writeln('No sessions.');
      return 0;
    }
    for (final s in sessions) {
      final date = s.createdAt.toLocal();
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final turns = s.turnCount ~/ 2; // user+assistant pairs = turns
      stdout.writeln(
        '${s.label.padRight(20)}  $dateStr  ${turns.toString().padLeft(3)} turns',
      );
    }
    return 0;
  }
}
