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
