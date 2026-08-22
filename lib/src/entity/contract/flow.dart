/// `flow` — how truth moves between copies: contact and movement. The
/// operations survive because git does not do them; the typed result algebra
/// that used to enumerate every case here (`Carried`, `NothingToCarry`,
/// `SourceOutOfReach`, `MovedApart`, `RefusedByGate`) is the same shape as
/// `action.dart`'s retired `Outcome` — a compare-and-swap-era taxonomy for a
/// primitive that now reads a live `git fetch`/`git push` result instead of
/// comparing against a stored record — and is cut with it (owed: the real
/// return shape, once `git fetch`/`git push`'s own reporting is measured the
/// way the substrate page measures the rest).
library;

import 'instance.dart';
import 'spine.dart';

/// The slice of `Copy` this component owns.
abstract interface class CopyFlow {
  /// Learn what [source] holds, for one instance or for all of them: a
  /// `git fetch`, which moves the remote-tracking refs and nothing else.
  ///
  /// Instances this copy did not know about arrive by the same act —
  /// discovery is contact, never a second mechanism.
  /// Throws `SourceUnreachable` when the source cannot be reached.
  Future<ContactReport> contact(String source, {Instance? about});

  /// Move one instance against one source. The only movement call there is:
  /// sets, scopes and aggregation belong to the caller.
  Future<void> move(
    Instance instance, {
    required String source,
    required Direction direction,
  });

  /// Move the class itself — the declaration and what the thing ships —
  /// against one source, by the same verb. The class has a line of its own
  /// and is never listed among the instances. A [Direction.bringCurrent] that
  /// carried anything is followed by a refit, so a copy that never carried
  /// the declaration can run a verb after it.
  Future<void> moveClass({
    required String source,
    required Direction direction,
  });
}

enum Direction {
  /// Give what this copy has and the source lacks.
  publish,

  /// Take what the source has and this copy lacks.
  bringCurrent,

  /// Both, where both are true.
  sync,
}

/// What one contact learned, as it learned it — a return value, never a
/// record. Nothing of ours stores this: standing against a source is read
/// live from the remote-tracking refs the fetch just moved, by
/// `git rev-list --left-right --count`, every time it is asked.
final class ContactReport {
  const ContactReport({
    required this.source,
    required this.at,
    required this.positions,
    required this.discovered,
  });
  final String source;
  final Instant at;

  /// What the source held, per instance, as of this contact — what this
  /// fetch saw. Later standing answers are measured afresh, not read here.
  final Map<String, Point> positions;

  /// Instances this copy did not know existed until now.
  final List<String> discovered;
}
