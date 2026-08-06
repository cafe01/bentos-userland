/// The machine: what the session owes, read at a commit.
///
/// **The face never derives this.** The state is a fold the entity itself
/// performs over its own tree, and a client that counted messages to guess it
/// would be a second implementation of the machine, drifting the day the entity
/// gains a noun.
library;

import 'coordinate.dart';
import 'primitive.dart';

/// What the session owes at a point in history.
enum SessionState {
  /// Nothing is owed. A screen may be read and a person may speak.
  idle,

  /// A prompt or a covered set of results is on the floor; the reply is owed.
  owesInference,

  /// A reply opened calls that are not yet covered.
  owesResults,
}

/// The fold, whole. `messages` and `commit` are here because a caller that
/// pinned a screen needs to say where it pinned it.
final class Fold {
  const Fold({
    required this.state,
    required this.openCalls,
    required this.messages,
    required this.commit,
  });

  final SessionState state;

  /// The call ids still uncovered. Empty in every state but [SessionState
  /// .owesResults] — and it is what `result` offers a person to answer.
  final List<String> openCalls;

  final int messages;

  /// Null only when the instance has not been born, where nothing is owed.
  final Sha? commit;
}

/// The reader of the machine. One method, because the entity has one fold.
abstract interface class MachineReader {
  /// [asOf] pins the reading. Absent, it folds at the tip — which is what a
  /// caller wants exactly once, before it has a commit to pin everything else
  /// to.
  Future<Fold> fold(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });
}
