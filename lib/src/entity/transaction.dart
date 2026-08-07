import '../git/model/commit.dart';

/// The `<old> <new> <ref>` triple the reference-transaction hook reads off
/// stdin, one line per ref moving in the transaction.
///
/// **It is not [RefUpdate], and the distinction is the point.** `RefUpdate` is
/// the *result* of a compare-and-swap this system asked for; this is the
/// substrate's own account of a swap already in flight, arriving from outside.
/// Two different facts under one name is exactly the defect this design closes
/// elsewhere, and the three fields rhyming is not a reason to reintroduce it.
final class TransactionRefUpdate {
  const TransactionRefUpdate({
    required this.old,
    required this.commit,
    required this.ref,
  });

  /// The value the ref held before this transaction, or [Commit.zero] for a
  /// birth.
  final Commit old;

  /// The value the transaction moves the ref to, or [Commit.zero] for a
  /// deletion.
  final Commit commit;

  /// The full ref name, e.g. `refs/heads/demo`.
  final String ref;

  /// Parses one stdin line. Throws [FormatException] on anything that is not
  /// three whitespace-separated fields — the shim never hands this a line it
  /// did not read verbatim from Git, so a malformed line is a broken contract
  /// with the substrate rather than a typo, and degrading it into a triple with
  /// an empty field would produce something dispatch then matches against.
  factory TransactionRefUpdate.parse(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
      throw FormatException('expected "<old> <new> <ref>"', line);
    }
    return TransactionRefUpdate(
      old: Commit(parts[0]),
      commit: Commit(parts[1]),
      ref: parts[2],
    );
  }

  @override
  String toString() => '${old.short} ${commit.short} $ref';
}
