/// `chat` with no verb — the loop a person actually sits in.
///
/// No chrome: a line is read, an act is committed, what landed is printed, and
/// the prompt comes back. `Ctrl-D` leaves. `Ctrl-C` cancels the **wait**, never
/// the circuit — the entity keeps working and the next look shows where it got
/// to, because an act already committed is not undone by looking away.
library;

import 'dart:io';

import '../lens.dart';
import '../turn.dart';
import 'chat_base_command.dart';

final class ReplCommand extends ChatBaseCommand {
  ReplCommand() {
    argParser.addOption(
      'timeout',
      defaultsTo: '180',
      help: 'Seconds to wait for each turn to come to rest.',
    );
  }

  @override
  String get name => 'repl';

  @override
  String get description => 'Sit in the conversation (the default verb).';

  @override
  String get invocation => 'chat [-s <session>]';

  @override
  Future<int> run() async {
    final session = this.session;
    final limit = Duration(
      seconds: int.tryParse(argResults!['timeout'] as String) ?? 180,
    );

    if (await session.tip() == null) {
      stderr.writeln(
        'chat: ${session.coord} has not been opened — open it with `chat new`',
      );
      return 1;
    }

    // Where the conversation stands, so that sitting down is joining it rather
    // than starting in the dark.
    for (final line
        in renderTranscript(await session.transcript(), Lens.conversation)) {
      stdout.writeln(line);
    }

    var interrupted = false;
    final signals = ProcessSignal.sigint.watch().listen((_) {
      interrupted = true;
    });

    try {
      while (true) {
        stdout.write('> ');
        final line = stdin.readLineSync();
        if (line == null) {
          // Ctrl-D. The newline is ours: the terminal printed nothing.
          stdout.writeln();
          return 0;
        }
        // A signal raised while the terminal was blocking here arrives now, and
        // it belongs to no turn: it is dropped rather than cancelling the turn
        // about to start.
        interrupted = false;
        if (line.trim().isEmpty) continue;

        final turn = await takeTurn(
          session,
          line,
          lens: Lens.conversation,
          limit: limit,
          cancelled: () => interrupted,
        );
        for (final rendered in turn.lines) {
          stdout.writeln(rendered);
        }
        switch (turn.outcome) {
          case TurnOutcome.cancelled:
            stderr.writeln('-- stopped looking; the turn is still running');
          case TurnOutcome.timedOut:
            stderr.writeln('-- still working after ${limit.inSeconds}s');
          case TurnOutcome.refused:
            stderr.writeln('-- refused; nothing was said');
          case TurnOutcome.rested:
            break;
        }
      }
    } finally {
      await signals.cancel();
    }
  }
}
