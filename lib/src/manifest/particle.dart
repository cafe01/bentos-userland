/// The periodic-table vocabulary, encoded as data for the `edit` verb.
///
/// This is the Standard Model (`hq/workshop/bentos-agent/science/bentos-standard-model.md`)
/// made machine-readable — the SOURCE OF TRUTH the `edit` verb speaks. It exists so
/// that the body never has to ask which realm an edit targets, whether a particle
/// takes a handle, or whether its content arrives on stdin: the particle NAME
/// answers all three. This is what makes `--add-trait` legal and `--add-realm`
/// impossible (Standard Model §V — realm is a function of the particle).
///
/// CONTRACT, NOT IMPLEMENTATION. The three tables below ARE the spec — they are
/// filled in deliberately so John does not re-derive them from the prose doc. The
/// behaviour that consumes them (lookup, validation) is the work to implement.
library;

/// Which container a particle lives in. Derived, never asked.
enum Realm { abstract_, concrete }

/// Whether a particle is addressed by a handle.
///
/// - [named]    — many siblings, each with a `name=` handle (trait, principle…).
///                The handle rides argv: `--add-trait <name>`.
/// - [singleton] — exactly one per atom, no handle (essence, purpose). No argv
///                name; `--set-essence` reads stdin, that is the whole address.
enum Arity { named, singleton }

/// A particle's editable profile — realm + arity. `kind` (prose vs scalar) is
/// implicit: every particle's body is prose and arrives on STDIN. Attributes
/// (the scalar, argv-borne axis) are a separate table ([editableAttrs]).
final class ParticleSpec {
  const ParticleSpec(this.realm, this.arity);
  final Realm realm;
  final Arity arity;
}

/// The editable particles — the prose-bodied terms `edit` v1 mutates.
///
/// SCOPE (v1, settled in the contract):
///   IN  — the prose particles below: identity (essence, purpose, trait),
///         capacity/protocol, guidance (principle), learning (knowledge,
///         pattern, antipattern). These are plasticity's daily surface:
///         evolve a trait, sharpen a principle, retire an antipattern.
///   OUT — the RELATION particles `requires` / `attracts`. Their shape breaks
///         the prose-on-stdin model (`requires` body is a bare id; `attracts`
///         is pure attributes `match` + `strength`, no body, no handle). They
///         are structural composition, edited rarely, and belong to a v2 pass
///         with its own flag shape. The body must REJECT `--*-requires` /
///         `--*-attracts` with a "not in v1 scope" error, never silently no-op.
///   OUT — assembly particles (atom/molecule/organism/data): not editable
///         content; molecules/organisms are pure composition, owned elsewhere.
const Map<String, ParticleSpec> editableParticles = {
  // Identity (abstract)
  'essence': ParticleSpec(Realm.abstract_, Arity.singleton),
  'purpose': ParticleSpec(Realm.abstract_, Arity.singleton),
  'trait': ParticleSpec(Realm.abstract_, Arity.named),
  // Capacity (split across realms — the dynamis/energeia pair)
  'capacity': ParticleSpec(Realm.abstract_, Arity.named),
  'protocol': ParticleSpec(Realm.concrete, Arity.named),
  // Guidance (abstract)
  'principle': ParticleSpec(Realm.abstract_, Arity.named),
  // Learning (concrete)
  'knowledge': ParticleSpec(Realm.concrete, Arity.named),
  'pattern': ParticleSpec(Realm.concrete, Arity.named),
  'antipattern': ParticleSpec(Realm.concrete, Arity.named),
};

/// Relation particles — NAMED here only so the parser can give a precise
/// "deferred to v2" error instead of an "unknown particle" one. Never editable
/// in v1.
const Set<String> v2RelationParticles = {'requires', 'attracts'};

/// Editable atom-level ATTRIBUTES — the scalar axis, set via `--set-<attr>` with
/// the value on ARGV (never stdin). Per the pure atom (Standard Model §VI) the
/// only attribute an atom carries is `v`. The map is a set today; it exists as a
/// table so a future attribute is a one-line addition, not a new code path.
const Set<String> editableAttrs = {'v'};

/// Resolve a particle name to its spec, or null if it is not a v1-editable
/// particle. The caller distinguishes "unknown" from "v2-deferred" via
/// [v2RelationParticles]. (Lookup is trivial; it is named so the parser depends
/// on an intention, not a literal map access.)
ParticleSpec? lookupParticle(String name) => editableParticles[name];
