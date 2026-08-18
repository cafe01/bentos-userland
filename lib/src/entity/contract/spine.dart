/// The type spine — design §4.
///
/// Every component page compiles against these. They are values: immutable,
/// comparable, serializable, and free of any dependency on git, on the place,
/// or on a running process.
library;

/// Who acted. Supplied by whoever acts (R2.3.3, and the floor demand in §3 of
/// the requirements); never derived from the machine's owner.
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
/// date it reached this copy (R2.6.4, R2.2.3).
typedef Instant = DateTime;

/// What a source is to this copy. A source may hold both.
enum Role { publishTo, follow }

/// When an instance moves against a source (R2.6.3).
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

/// An address the substrate accepts, with the roles and cadence this copy
/// gives it. Held by the copy and by nobody else (R2.6.1).
final class Source {
  const Source({
    required this.name,
    required this.address,
    required this.roles,
    required this.cadence,
  });
  final String name;
  final String address;
  final Set<Role> roles;
  final Cadence cadence;
}

/// How this copy's line relates to a source's, as of the last contact
/// (R2.9.1). The counts are part of the answer, never an extra (R2.9.1a).
enum Relation { current, behind, ahead, diverged, unknown }

/// A standing answer. There is no constructor path to a dated `unknown` or an
/// undated `behind` (R2.9.2): [Standing.unknown] is the one undated value, and
/// [Standing.known] requires the age.
final class Standing {
  const Standing.known({
    required this.relation,
    required this.behind,
    required this.ahead,
    required Instant this.contacted,
  }) : assert(relation != Relation.unknown, 'unknown carries no age');

  /// The honest answer for a source never contacted about this instance.
  const Standing.unknown()
      : relation = Relation.unknown,
        behind = 0,
        ahead = 0,
        contacted = null;

  final Relation relation;

  /// Landings the source holds that this copy lacks.
  final int behind;

  /// Landings this copy holds that the source lacks.
  final int ahead;

  /// When the contact this answer rests on happened. Null only for
  /// [Relation.unknown], which is the one value that carries no age (R2.9.2).
  final Instant? contacted;

  @override
  bool operator ==(Object other) =>
      other is Standing &&
      other.relation == relation &&
      other.behind == behind &&
      other.ahead == ahead &&
      other.contacted == contacted;

  @override
  int get hashCode => Object.hash(relation, behind, ahead, contacted);

  @override
  String toString() =>
      'Standing(${relation.name}, behind: $behind, ahead: $ahead, contacted: $contacted)';
}
