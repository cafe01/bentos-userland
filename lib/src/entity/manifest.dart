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
final class Manifest {
  const Manifest({
    required this.type,
    required this.actions,
    required this.fields,
  });

  /// What the entity claims to be — a brain, a conversation, an inference
  /// session. **The declaration is what a type is**: nothing validates the
  /// claim, and conformance is unchecked by design, so interoperability rests
  /// on declarations agreeing rather than on a checker agreeing with them.
  final String type;

  /// The action vocabulary: the nouns this type admits. Its product with the
  /// three phases *is* the entity's event vocabulary — which is why nothing
  /// declares events anywhere.
  final List<String> actions;

  /// The document entire, as parsed. The escape hatch that keeps an unsettled
  /// schema from being frozen by this type.
  final Map<String, Object?> fields;

  /// The path the manifest stands at in the genesis tree.
  static const String path = 'manifest.yaml';

  /// Parses a manifest document. Construction's body; the shape it must
  /// produce is this class.
  factory Manifest.parse(String source) =>
      throw UnimplementedError('Manifest.parse');
}
