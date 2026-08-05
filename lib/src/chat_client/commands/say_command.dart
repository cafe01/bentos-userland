/// `chat say` — the keyboard. One act, followed to rest, and what landed is
/// printed: an act whose consequence is invisible is an act a person cannot use.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../lens.dart';
import '../turn.dart';
import 'chat_base_command.dart';

final class SayCommand extends ChatBaseCommand {
  SayCommand() {
    argParser
      ..addFlag(
        'wait',
        defaultsTo: true,
        help: 'Wait for the session to come back to rest before returning.\n'
            'The armed circuit is asynchronous: the act that deposits a prompt\n'
            'returns as soon as it has committed, and the reply lands seconds\n'
            'later. Without the wait there is nothing to print yet.',
      )
      ..addOption(
        'timeout',
        defaultsTo: '180',
        help: 'Seconds to wait for rest before giving up on the wait.',
      );
  }

  @override
  String get name => 'say';

  @override
  String get description => 'Say something to the conversation.';

  @override
  String get invocation => 'chat [-s <session>] say <text>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      throw UsageException('say: <text> is required', usage);
    }
    final session = this.session;

    if (!(argResults!['wait'] as bool)) {
      return session.run('user.say', [rest.single]);
    }

    final seconds = int.tryParse(argResults!['timeout'] as String);
    if (seconds == null) {
      throw UsageException('say: --timeout takes seconds', usage);
    }

    final turn = await takeTurn(
      session,
      rest.single,
      lens: Lens.conversation,
      limit: Duration(seconds: seconds),
    );
    for (final line in turn.lines) {
      stdout.writeln(line);
    }
    if (turn.outcome == TurnOutcome.timedOut) {
      stderr.writeln(
        'chat say: still working after ${seconds}s — it is not lost, '
        'look again with `chat monitor`',
      );
    }
    return turn.exitCode;
  }
}
