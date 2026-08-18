/// `flow` — how truth moves between copies: contact, movement, arrival.
library;

import 'instance.dart';
import 'spine.dart';

/// The slice of `Copy` this component owns.
abstract interface class CopyFlow {
  /// Learn what [source] holds, for one instance or for all of them.
  ///
  /// Refreshes the age every standing against that source rests on (§2.9),
  /// and enters instances this copy did not know about as existing there
  /// (R2.6.2 — discovery is contact, never a second mechanism).
  /// Throws `SourceUnreachable` when the source cannot be reached.
  Future<ContactReport> contact(String source, {Instance? about});

  /// Move one instance against one source. The only movement call there is:
  /// sets, scopes and aggregation belong to the caller (place R31).
  Future<MoveReport> move(
    Instance instance, {
    required String source,
    required Direction direction,
  });

  /// Move the class itself — the declaration and what the thing ships —
  /// against one source, by the same verb. The class has a line of its own
  /// and is never listed among the instances. A [Direction.bringCurrent] that
  /// carried anything is followed by a refit, so a copy that never carried
  /// the declaration can run a verb after it.
  Future<MoveReport> moveClass({
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

/// One instance against one source. Named apart from an action's `Outcome`
/// on purpose: a movement and a landing are different events with different
/// obligations, and one type standing for both is how they get confused.
sealed class MoveReport {
  const MoveReport({required this.instance, required this.source});
  final String instance;
  final String source;
}

final class Carried extends MoveReport {
  const Carried({
    required super.instance,
    required super.source,
    required this.direction,
    required this.landings,
  });
  final Direction direction;
  final int landings;
}

/// The pair was already current. Nothing moved, and nothing was wrong.
final class NothingToCarry extends MoveReport {
  const NothingToCarry({required super.instance, required super.source});
}

/// The source could not be reached. Every standing against it keeps its last
/// age; nothing else in the caller's set is affected (R2.6.6).
final class SourceOutOfReach extends MoveReport {
  const SourceOutOfReach({
    required super.instance,
    required super.source,
    required this.because,
  });
  final String because;
}

/// Both hold landings the other lacks. Both lines are held here; nothing was
/// discarded and nothing was merged (§2.7).
final class MovedApart extends MoveReport {
  const MovedApart({
    required super.instance,
    required super.source,
    required this.here,
    required this.there,
  });
  final Point here;
  final Point there;
}

/// A declared gate refused an arriving landing (R2.3.6), in its own words.
final class RefusedByGate extends MoveReport {
  const RefusedByGate({
    required super.instance,
    required super.source,
    required this.rule,
    required this.words,
  });
  final String rule;
  final String words;
}

/// What one contact learned (R2.6.2).
final class ContactReport {
  const ContactReport({
    required this.source,
    required this.at,
    required this.positions,
    required this.discovered,
  });
  final String source;
  final Instant at;

  /// What the source held, per instance, as of this contact. What every later
  /// standing answer is read from.
  final Map<String, Point> positions;

  /// Instances this copy did not know existed until now.
  final List<String> discovered;
}
