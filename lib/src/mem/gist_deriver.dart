/// Derives the gist from a page body via the llm coreutil.
///
/// TARGET seam — stubbed. Wires live when llm composition is in place.
/// Honors manual override: when [manualGist] is given, returns it immediately
/// and skips derivation. Absent it, derives (currently returns null until wired).
final class GistDeriver {
  const GistDeriver();

  Future<String?> derive(String body, {String? manualGist}) async {
    if (manualGist != null) return manualGist;
    return null; // stub — wired in a future phase
  }
}
