/// One turn from the person's side: say it, wait for the circuit to come to
/// rest, and show what landed because of it.
///
/// The act returns before the answer does — a write deposits, the commit wakes
/// the listener, and the reply lands seconds later. Waiting is therefore a
/// separate faculty from acting, and the person who waits is the one who wants
/// to see.
library;

import 'coordinate.dart';
import 'primitive.dart';
import 'transcript.dart';

/// How a turn ended.
enum TurnOutcome {
  /// The session came back to rest and everything it owed has landed.
  rested,

  /// The wait ran out. Nothing is lost — the circuit is still running.
  timedOut,

  /// The person interrupted the wait. Same: interrupting is not undoing, and an
  /// act already committed is not undone by looking away.
  cancelled,

  /// The act itself was refused, and nothing was deposited. A verdict: the
  /// same act will be refused again.
  refused,

  /// The ref moved under the act before it could land, and nothing was
  /// deposited. Not a verdict: nobody decided anything, and a caller that
  /// reads the tip again and says it again terminates. Never folded into
  /// [refused] — a face that cannot tell the two apart cannot answer either
  /// one correctly.
  contested,
}

final class TurnResult {
  const TurnResult({
    required this.outcome,
    required this.landed,
    required this.from,
    required this.to,
    this.refusal,
  });

  final TurnOutcome outcome;

  /// What the session gained, under the lens the caller asked for — the person's
  /// own words left out, since they have just typed them.
  final List<RenderedTurn> landed;

  /// The commit before the act, and the commit the reading was pinned to. Null
  /// [from] is a session that had not been born.
  final Sha? from;
  final Sha? to;

  /// Why the act did not land, **in the floor's own words** — a refusal's
  /// reason or a stumble's report, whichever the floor gave. Both are values
  /// and not faults: what stands behind them is part of how the entity works,
  /// and a face that paraphrased either would be answering for a layer it
  /// does not own. Null unless [outcome] is [TurnOutcome.refused] or
  /// [TurnOutcome.contested].
  final String? refusal;
}

/// Waiting for the session to come to rest.
///
/// **A port because the mechanism is owed a change.** Today the only way to know
/// is to fold again and again; what this wants is `notify` — a signal to a live
/// process — and when the primitive offers it, this interface is where the swap
/// happens and nothing above it moves.
abstract interface class Rest {
  /// Returns [TurnOutcome.rested], [TurnOutcome.timedOut] or
  /// [TurnOutcome.cancelled]; never [TurnOutcome.refused] or
  /// [TurnOutcome.contested], which are the act's words and not the wait's.
  Future<TurnOutcome> awaitRest(
    Coordinate coord, {
    required Duration limit,
    bool Function()? cancelled,
    Vantage vantage = const Vantage.here(),
  });
}
