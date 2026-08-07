/// Which channel a verb acts on when nobody typed one.
///
/// **The pointer belongs to the shell.** Two terminals in two conversations is
/// the normal gesture, so the ambient channel is an environment variable and
/// never a file — a pointer on disk would make the two terminals fight over one
/// cursor. The variable's name is derived from the ontology by the mechanical
/// rule the primitive lays down (`bentos.chat` → `BENTOS_CHAT_CHANNEL`), so
/// there is no registry to maintain and you may stand in an LLM session and a
/// chat channel at the same time.
///
/// Precedence: **argument, then variable, then the place**. The third step is
/// not a store: it derives from disk the way `mem`'s and `place`'s vantage do,
/// by asking the installation which instances it carries. One is the answer;
/// several is an ambiguity that gets listed rather than guessed, because the
/// ambiguity is information and picking for the caller would be inventing an
/// intention.
library;

import '../channel.dart';

/// The variable the shell carries the ambient channel in.
const String channelVariable = 'BENTOS_CHAT_CHANNEL';

/// Where a resolved coordinate came from — reported by `where`, so that a person
/// who is surprised by which channel they are in can see which step answered.
enum CoordinateSource {
  argument('-c'),
  environment(channelVariable),
  place('the place');

  const CoordinateSource(this.label);

  final String label;
}

/// A channel's address: the ontology and the instance, and which step named it.
final class ChatCoordinate {
  const ChatCoordinate(this.name, this.source);

  /// The instance id — the word a person joins.
  final String name;

  final CoordinateSource source;

  String get whole => '$chatOntology:$name';

  /// `bentos.chat:fabrica` or the bare `fabrica`, since a hand that is already
  /// inside one ontology should not have to spell it. A coordinate naming
  /// another ontology is a mistake and never a channel.
  static String parse(String given) {
    final colon = given.indexOf(':');
    if (colon < 0) {
      if (given.isEmpty) throw const MalformedCoordinate('');
      return given;
    }
    final ontology = given.substring(0, colon);
    final name = given.substring(colon + 1);
    if (ontology != chatOntology) throw MalformedCoordinate(given);
    if (name.isEmpty || name.contains(':')) throw MalformedCoordinate(given);
    return name;
  }
}

/// A coordinate that is not one of this ontology's.
final class MalformedCoordinate implements Exception {
  const MalformedCoordinate(this.given);

  final String given;

  @override
  String toString() => given.isEmpty
      ? '$chatOntology: an empty channel is not a coordinate'
      : "$chatOntology: not a channel of this ontology: '$given'";
}

/// Nobody said which channel, and the place does not answer for one.
final class NoAmbientChannel implements Exception {
  const NoAmbientChannel(this.anchor, this.candidates);

  final String anchor;

  /// What the place carries. Empty means the installation holds no channel at
  /// all; more than one means the place cannot answer and the caller must.
  final List<String> candidates;

  @override
  String toString() => candidates.isEmpty
      ? '$chatOntology: no channel here — name one with -c, or set $channelVariable '
          '(searched from $anchor)'
      : '$chatOntology: which channel? ${candidates.join(', ')} — name one with -c, '
          'or set $channelVariable';
}
