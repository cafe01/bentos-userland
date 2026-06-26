/// Word count for a page body — the reading-weight signal for the size hint.
///
/// Counts whitespace-delimited words, ignores frontmatter. Returns the [Nw]
/// hint string when count is at or above [threshold]; returns null below it.
final class WordCount {
  const WordCount({this.threshold = 120});

  final int threshold;

  /// Count words in [body] (frontmatter already stripped).
  int count(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// Returns `[Nw]` when [body] meets or exceeds [threshold]; null otherwise.
  String? hint(String body) {
    final n = count(body);
    return n >= threshold ? '[${n}w]' : null;
  }
}
