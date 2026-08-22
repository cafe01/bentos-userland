/// The type spine.
///
/// Every component page compiles against these. They are values: immutable,
/// comparable, serializable, and free of any dependency on git, on the place,
/// or on a running process.
library;

/// Who acted. Supplied by whoever acts; never derived from the machine's
/// owner.
final class Actor {
  const Actor({required this.name, required this.address});
  final String name;
  final String address;

  @override
  bool operator ==(Object other) =>
      other is Actor && other.name == name && other.address == address;

  @override
  int get hashCode => Object.hash(name, address);

  @override
  String toString() => '$name <$address>';
}

/// A position on one instance's line. Opaque, totally ordered *within* one
/// instance and never across instances or entities.
extension type const Point(String _id) implements Object {}

/// An instant of the world. Always the date the action was taken, never the
/// date it reached this copy.
typedef Instant = DateTime;

/// What a source is to this copy. A source may hold both.
enum Role { publishTo, follow }

/// When an instance moves against a source.
sealed class Cadence {
  const Cadence();
}

final class ByHand extends Cadence {
  const ByHand();
}

final class OnLanding extends Cadence {
  const OnLanding();
}

final class OnArrival extends Cadence {
  const OnArrival();
}

final class OnClock extends Cadence {
  const OnClock(this.every);
  final Duration every;
}

/// How this copy's line relates to a source's, measured live against that
/// source's remote-tracking ref by `git rev-list --left-right --count`: the
/// commits each side holds that the other lacks. There is no `unknown`
/// relation here — a copy that has never contacted a source has no
/// remote-tracking ref to measure against at all, which is a different and
/// honest statement than any of these four, made by the absence of a
/// [Standing] rather than by a fifth value on this enum.
enum Relation { current, behind, ahead, diverged }

/// A standing answer: the outcome of measuring one instance against one
/// source, right now. It carries no age — what is dated is the last fetch,
/// and git already holds that on the remote-tracking ref itself, so nothing
/// here duplicates it.
final class Standing {
  const Standing({
    required this.relation,
    required this.behind,
    required this.ahead,
  });

  final Relation relation;

  /// Landings the source holds that this copy lacks.
  final int behind;

  /// Landings this copy holds that the source lacks.
  final int ahead;

  @override
  bool operator ==(Object other) =>
      other is Standing &&
      other.relation == relation &&
      other.behind == behind &&
      other.ahead == ahead;

  @override
  int get hashCode => Object.hash(relation, behind, ahead);

  @override
  String toString() =>
      'Standing(${relation.name}, behind: $behind, ahead: $ahead)';
}
