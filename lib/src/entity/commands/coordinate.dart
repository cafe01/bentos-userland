/// A coordinate as the shell writes it: `<entity>:<instance>`, optionally with
/// a path — `<entity>:<instance>:<path>`.
///
/// **The coordinate is the argument.** Class-level verbs take a bare name and
/// resolve it by walking up the tree of places; instance-level verbs take one
/// of these. The vantage the walk starts from is moved by `-C`, exactly as
/// `place` and `mem` take their globals before the verb.
///
/// This is a *selection*, never a runtime address: two of the dimensions are
/// refs, and one does not write to a ref. Coordinate resolves; path operates.
final class Coordinate {
  const Coordinate({required this.entity, required this.instance, this.path});

  final String entity;
  final String instance;

  /// The path within the instance's tree, for the verbs that read content.
  final String? path;

  /// Parses `<entity>:<instance>[:<path>]`. Throws [FormatException] when the
  /// instance is missing — a coordinate without one names a class, and the
  /// verbs that take a class take a bare name instead.
  factory Coordinate.parse(String text) {
    final parts = text.split(':');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw FormatException('expected <entity>:<instance>', text);
    }
    return Coordinate(
      entity: parts[0],
      instance: parts[1],
      path: parts.length > 2 ? parts.sublist(2).join(':') : null,
    );
  }

  @override
  String toString() =>
      path == null ? '$entity:$instance' : '$entity:$instance:$path';
}

/// The environment variable an ontology's ambient coordinate is read from:
/// upper case, every separator a underscore — `bentos.llm` reads `BENTOS_LLM`.
///
/// **A mechanical rule and not a registry.** Derived from the name, so a new
/// ontology asks nobody's permission and nothing has to be kept in step; and one
/// variable per ontology, so a caller stands in an LLM session and a chat
/// channel at once without either erasing the other.
///
/// The convention belongs to the primitive rather than to each face: whoever
/// answers for coordinates answers for how one is found when nobody typed it.
String ambientVariableFor(String entity) =>
    entity.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');

/// Where an ambient coordinate came from, so that a verb can say which step
/// answered rather than leaving a caller to guess.
enum CoordinateSource {
  /// The caller typed it. Always wins — it is what keeps every verb scriptable
  /// with no environment at all.
  argument,

  /// The occurrence a hook is firing for: the instance the event landed on,
  /// exported by the shim. It outranks a pointer because it is a fact about
  /// *this* transaction, while a pointer is a fact about somebody's session.
  occurrence,

  /// The ontology's ambient variable — a session's pointer, the shell's own.
  pointer,
}

/// The environment names the shim exports the occurrence under, and the same
/// ones `run` lays for a body. One vocabulary, so that a function woken by a
/// reaction and a function called by hand read their context identically.
/// **Two registers.** The address is always laid — a function called by hand
/// through `run` gets it and nothing more, and that absence is its answer to
/// *why am I running*: nobody woke me. The occurrence is laid only by dispatch,
/// on a body a subscription woke, so nothing has to go find out where it is or
/// why it is up.
abstract final class OccurrenceEnvironment {
  static const String entity = 'BENTOS_ENTITY';
  static const String instance = 'BENTOS_INSTANCE';
  static const String coordinate = 'BENTOS_COORD';
  static const String place = 'BENTOS_PLACE';

  static const String event = 'BENTOS_EVENT';
  static const String phase = 'BENTOS_PHASE';
  static const String noun = 'BENTOS_NOUN';

  /// The act's commit — the value the ref takes.
  static const String sha = 'BENTOS_SHA';

  /// The value the ref held before it — **the parent**. A gate at `.attempted`
  /// judges the act where it stands, and where it stands is here: at that phase
  /// the ref has not moved, so folding at the tip would be leaning on the
  /// substrate's transaction timing to be right.
  static const String old = 'BENTOS_OLD';
}
