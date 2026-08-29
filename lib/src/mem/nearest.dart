/// Nearest-name matching, shared by every hint that must answer "not that —
/// this one?": a mistyped topic (`unresolved-topic`) and a mistyped option
/// (`unknown-option`) are the same problem once the source of candidates
/// changes. See `output-contract.md` §6.
///
/// Ranked by edit distance, ascending: cheapest to reach from what was
/// typed. Self-contained — no fuzzy-match package, just the textbook
/// algorithm — so it costs nothing to keep beside the tool it serves.
///
/// **[maxDistance] is what makes the answer a suggestion rather than a
/// ranking.** Without a ceiling the nearest name is whatever came closest in
/// a pool that may hold nothing close at all, and the line then teaches a
/// falsehood in a confident voice: `mem --version` answered *did you mean
/// --attention?*, and a topic nobody ever wrote answered with three unrelated
/// pages. Two edits is the measured seam — `--shapee` still reaches `--shape`,
/// and neither of those two cases survives it. Beyond it the honest answer is
/// no answer, and the caller is left with the bare fact and the index.
List<String> nearestNames(
  String typed,
  Iterable<String> candidates, {
  int cap = 3,
  int maxDistance = 2,
}) {
  final scored = [
    for (final candidate in candidates)
      if (_levenshtein(typed, candidate) case final d when d <= maxDistance)
        (name: candidate, distance: d),
  ]..sort((a, b) => a.distance.compareTo(b.distance));
  return [for (final s in scored.take(cap)) s.name];
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + substitutionCost;
      current[j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
