/// `manifest` — the declaration. The primitive's only contract with the thing
/// (R2.5.1): it reads this and never the contents.
library;

import 'spine.dart';

final class Manifest {
  const Manifest({
    required this.name,
    required this.kind,
    required this.instanceName,
    required this.rhythm,
    this.functions = const {},
    this.gates = const [],
    this.reconciliation,
    this.fields = const {},
  });

  /// The entity's name, in DNS notation, its rightmost label the ontology it
  /// claims — `.chat`, `.mem`, `.place`.
  final String name;

  /// What kind of thing it is. The host maps this to the lens that opens it
  /// (Places §8.3); the primitive only carries it.
  final String kind;

  /// How an instance is titled for a desk that lists it (R2.5.2) — its title,
  /// never the substrate's handle.
  final InstanceNaming instanceName;

  /// The roles and cadence a fresh copy gives its first source, so that
  /// installing asks only *where* (R2.5.2, place R11).
  final Rhythm rhythm;

  /// Verbs the thing ships, by name (R2.8.1).
  final Map<String, String> functions;

  /// Rules a landing must satisfy on any copy (R2.3.6).
  final List<GateRule> gates;

  /// Set when divergence is the thing's own to resolve (R2.7.4).
  final ReconciliationRule? reconciliation;

  /// Everything declared that the primitive does not read. Carried, never
  /// interpreted, never a reason to refuse (R2.5.3).
  final Map<String, Object?> fields;
}

/// Where an instance's displayable title comes from.
///
/// The title must be answerable on a copy that holds no content (R2.1.5), so
/// the only mechanism the primitive supports is the one that rides the
/// landing itself: every action may carry the instance's title as a trailer,
/// and the newest landing carries the current one. A rule that must read a
/// file has not met R2.1.5 and is refused at install.
final class InstanceNaming {
  const InstanceNaming({required this.fallback});

  /// What to show for an instance whose landings carry no title — a fresh one,
  /// or one whose author declared none. Never the substrate's handle.
  final String fallback;
}

final class Rhythm {
  const Rhythm({required this.roles, required this.cadence});
  final Set<Role> roles;
  final Cadence cadence;
}

/// A rule a landing must satisfy, applied before landing, on every copy
/// alike (R2.3.6). Its own words come back in `Gated`.
final class GateRule {
  const GateRule({required this.name, required this.run});
  final String name;
  final String run;
}

/// What a thing does with two lines of one instance when it says divergence
/// is its own (R2.7.4). What the rule lands is an ordinary action whose actor
/// is the rule, named here.
final class ReconciliationRule {
  const ReconciliationRule({required this.actor, required this.run});
  final Actor actor;
  final String run;
}
