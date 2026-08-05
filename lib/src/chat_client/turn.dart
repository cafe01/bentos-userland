/// One turn from the person's side: say it, wait for the circuit to come to
/// rest, and show what landed because of it.
///
/// `chat say` and the REPL are the same three steps — the REPL only repeats
/// them — so they are written once here and neither owns them.
library;

import 'lens.dart';
import 'session.dart';

/// How a turn ended.
enum TurnOutcome {
  /// The session came back to rest and everything it owed has landed.
  rested,

  /// The wait ran out. Nothing is lost — the circuit is still running.
  timedOut,

  /// The person interrupted the wait. Same: the circuit is still running.
  cancelled,

  /// The act itself was refused, and nothing was deposited.
  refused,
}

final class TurnResult {
  const TurnResult(this.outcome, this.lines, {this.exitCode = 0});

  final TurnOutcome outcome;

  /// What landed since the act, under the lens — the person's own words left
  /// out, since they have just typed them.
  final List<String> lines;

  final int exitCode;
}

/// Deposit a prompt and follow it to rest.
///
/// [cancelled] is polled between reads: the wait is what a person interrupts,
/// never the circuit. Interrupting is not undoing — the entity keeps working,
/// and the next look shows where it got to.
Future<TurnResult> takeTurn(
  Session session,
  String text, {
  required Lens lens,
  Duration limit = const Duration(seconds: 180),
  bool Function()? cancelled,
}) async {
  final before = await session.tip();

  final deposited = await session.run('user.say', [text]);
  if (deposited != 0) {
    return TurnResult(TurnOutcome.refused, const [], exitCode: deposited);
  }

  final outcome = await _rest(session, limit, cancelled);
  return TurnResult(
    outcome,
    await landedSince(session, before, lens),
    exitCode: outcome == TurnOutcome.rested ? 0 : 1,
  );
}

/// What the session gained since [before], read as one pinned screen.
///
/// The person's own act heads the new run and is dropped: they typed it, and a
/// face that echoes it back is a face that pads.
Future<List<String>> landedSince(
  Session session,
  String? before,
  Lens lens,
) async {
  final at = await session.tip();
  if (at == null) return const [];

  final already =
      before == null ? <String>{} : (await session.messageNames(asOf: before))
          .toSet();

  final fresh = (await session.transcript(asOf: at))
      .where((stored) => !already.contains(stored.path))
      .toList();
  while (fresh.isNotEmpty && speakerOf(fresh.first.message) == Speaker.you) {
    fresh.removeAt(0);
  }
  return renderTranscript(fresh, lens);
}

/// Poll the entity's own fold until it says idle.
///
/// Polling is the placeholder and it is named as one: what this wants is
/// `notify` — a signal to a live process — which the primitive does not offer
/// yet. When it does, this waits on a signal and the loop goes.
Future<TurnOutcome> _rest(
  Session session,
  Duration limit,
  bool Function()? cancelled,
) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (cancelled?.call() ?? false) return TurnOutcome.cancelled;
    if (await session.state() == 'idle') return TurnOutcome.rested;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return TurnOutcome.timedOut;
}
