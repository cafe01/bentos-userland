/// The size hint — a page body's word count, shown only when it crosses a blind
/// threshold. A curation cue (a heavy read), never a verdict. Pure.
final class WordCount {
  const WordCount({this.threshold = 120});

  final int threshold;

  /// Count whitespace-delimited words in [body]. Frontmatter is already
  /// stripped from a [MemPage] body.
  int count(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  /// `[Nw]` when [body] meets or exceeds [threshold]; null below it.
  String? hint(String body) {
    final n = count(body);
    return n >= threshold ? '[${n}w]' : null;
  }
}
