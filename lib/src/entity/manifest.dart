import 'package:yaml/yaml.dart';

/// The entity's self-description, carried **in band** — a file in the genesis
/// tree — and the entity system's only contract.
///
/// The primitive reads the manifest because the manifest is *about* the entity.
/// It never reads inside an instance's worktree, because what the contents mean
/// is the application's contract with itself.
///
/// # Deliberately minimal
///
/// What a manifest declares — how deep the declaration goes, whether a
/// FunctionDefinition is entity content while its executable is deployment,
/// what a plural entity's recursive materialization should bring down — is an
/// **open frontier**, and one that grows from use rather than from
/// anticipation. So this type states the two facts every consumer already
/// needs and refuses to invent the rest: the [type] the entity claims, and the
/// [actions] its vocabulary admits.
///
/// Everything else stays reachable as [fields], unparsed. That is the honest
/// shape for a schema that is not settled: the document is carried whole, the
/// parts we have decided are typed, and nothing is lost while we decide the
/// rest.
/// How many objects of a class coexist. The one thing the manifest says that a
/// primitive outside the entity must act on, which is why it is typed here and
/// the rest of the document is not.
enum Cardinality {
  /// One object, and the entity's pin is its state — a memory bank, a settings
  /// store.
  singular,

  /// Objects that coexist, none of them *the* one — conversations, cases, runs.
  plural,
}

final class Manifest {
  const Manifest({
    required this.name,
    required this.type,
    required this.actions,
    required this.cardinality,
    required this.functions,
    required this.reactions,
    required this.fields,
  });

  /// The dotted identity the entity was authored under, stated by the entity
  /// itself. **Blank when undeclared, never a throw** — a freshly authored
  /// entity has no manifest at all, which is the ordinary condition
  /// [Entity.install] must fall through rather than choke on; absence here is
  /// what lets its name precedence reach the source-derived fallback.
  final String name;

  /// What the entity claims to be — a brain, a conversation, an inference
  /// session. **The declaration is what a type is**: nothing validates the
  /// claim, and conformance is unchecked by design, so interoperability rests
  /// on declarations agreeing rather than on a checker agreeing with them.
  final String type;

  /// The action vocabulary: the nouns this type admits. Its product with the
  /// three phases *is* the entity's event vocabulary — which is why nothing
  /// declares events anywhere.
  final List<String> actions;

  /// How many objects of this class coexist — and therefore **what materializing
  /// the entity brings down**: a singular entity's pin *is* its state, so its
  /// tree is what a place holds it at; a plural entity has no single commit that
  /// could mean *all fifty conversations*, so what comes down is the class —
  /// genesis, with the structure and this document.
  ///
  /// **Absent means [Cardinality.plural]**, and the reason is honesty rather
  /// than frequency: undeclared, we do not know, and bringing genesis down
  /// brings what we know the thing *is*. Electing some branch as *the* state
  /// would be the primitive inventing ontology nobody gave it. Note that
  /// `create` leaves genesis empty, so *no manifest at all* is the ordinary
  /// condition of every freshly authored entity — the behaviour on absence is
  /// the common behaviour, and it has to be the conservative one.
  final Cardinality cardinality;

  /// What the entity ships, as `run` reads it: **the semantic name is the key
  /// and the executable is the value**, which is the whole reason a caller can
  /// name a verb and never a layout.
  ///
  /// Typed because it is the second thing a primitive outside the entity must
  /// act on. Everything else a function row declares — what it deposits, what
  /// it lands on — stays in [fields], because those are read by the floor and
  /// by arming, and `run` is forbidden to have an opinion about either.
  ///
  /// **Null against a declared name that ships no executable.** Declared and
  /// unrunnable is not the same absence as never declared, and collapsing the
  /// two would make a manifest's own omission read as the caller's typo.
  final Map<String, String?> functions;

  /// What each function reacts to: the function's semantic name against the
  /// event patterns its `on:` rows declare, verbatim and unvalidated.
  ///
  /// Typed for the same reason [functions] is — a primitive outside the entity
  /// acts on it. **Installing is reading this table and arming it**, which is
  /// what turns a per-seat `arm` written in code into a declaration read by the
  /// installer, and what lets a reaction survive being installed somewhere its
  /// author never saw.
  ///
  /// The patterns are **strings here on purpose**: parsing one is the arming
  /// component's business, and a manifest that could not be *read* because one
  /// row is misspelled would take the whole entity down over a typo in one
  /// reaction.
  final Map<String, List<String>> reactions;

  /// The document entire, as parsed. The escape hatch that keeps an unsettled
  /// schema from being frozen by this type.
  final Map<String, Object?> fields;

  /// The path the manifest stands at in the genesis tree.
  static const String path = 'entity.yaml';

  /// Parses a manifest document. Construction's body; the shape it must
  /// produce is this class.
  factory Manifest.parse(String source) {
    final document = loadYaml(source);
    final fields = <String, Object?>{
      if (document is Map)
        for (final entry in document.entries) '${entry.key}': _plain(entry.value),
    };
    return Manifest(
      name: '${fields['name'] ?? ''}',
      type: '${fields['type'] ?? ''}',
      actions: [
        if (fields['actions'] case final List<Object?> declared)
          for (final action in declared) '$action',
      ],
      cardinality: fields['cardinality'] == 'singular'
          ? Cardinality.singular
          : Cardinality.plural,
      functions: {
        if (fields['functions'] case final Map<String, Object?> declared)
          for (final entry in declared.entries)
            entry.key: switch (entry.value) {
              final Map<String, Object?> row when row['exec'] != null =>
                '${row['exec']}',
              _ => null,
            },
      },
      reactions: {
        if (fields['functions'] case final Map<String, Object?> declared)
          for (final entry in declared.entries)
            if (entry.value case final Map<String, Object?> row)
              if (row['on'] case final List<Object?> landings)
                entry.key: [for (final landing in landings) '$landing'],
      },
      fields: fields,
    );
  }

  /// The document as ordinary Dart, so that [fields] is an escape hatch and not
  /// a second library's types leaking through the contract.
  static Object? _plain(Object? node) => switch (node) {
        final Map<Object?, Object?> map => {
            for (final entry in map.entries) '${entry.key}': _plain(entry.value),
          },
        final List<Object?> list => [for (final item in list) _plain(item)],
        _ => node,
      };
}
