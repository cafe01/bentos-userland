/// A commit of the entity's history, by its object name.
///
/// A commit stores **the whole state, never a diff** — which is why *what an
/// action changed* is always derived and never recorded. The type is a value:
/// two handles to the same object are equal, and holding one costs nothing.
extension type const Commit(String sha) {
  /// True for the null object name — the value that means *this ref must not
  /// exist*, which is how a first action refuses to happen twice.
  bool get isZero => sha == zero.sha;

  /// The null object name Git writes for a ref that does not exist.
  static const Commit zero = Commit('0000000000000000000000000000000000000000');

  /// The abbreviated form, for a human reading a log.
  String get short => sha.length <= 7 ? sha : sha.substring(0, 7);
}

/// How one path changed between two commits.
enum ChangeKind { added, modified, deleted }

/// One path's change within a [Diff] — the unit an application reads when it
/// takes an action's payload.
final class Change {
  const Change({required this.path, required this.kind});

  final String path;
  final ChangeKind kind;

  @override
  String toString() => '${kind.name} $path';
}

/// What an action changed: the derived comparison of two trees.
///
/// Derived, always. The substrate stores states and the difference between two
/// of them is computed on demand, so a diff is a reading of the history and
/// never a record inside it.
final class Diff {
  const Diff(this.changes);

  final List<Change> changes;

  bool get isEmpty => changes.isEmpty;

  /// The paths touched, in the order the substrate reports them.
  List<String> get paths => [for (final c in changes) c.path];
}
