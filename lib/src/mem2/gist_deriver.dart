import 'dart:convert';
import 'dart:io' as io;

/// The llm seam: a page body in, its one-line navigation cue out. Injected so
/// tests stub it and never reach a live model.
typedef GistLlm = Future<String> Function(String body);

/// Derives a page's gist — the single navigation line, *what you'll find if you
/// open this page* — from its body, by handing the body to the [GistLlm] seam.
/// A manual gist wins and skips the seam entirely. A derivation that yields
/// nothing surfaces as [GistDerivationFailed]: the organ never writes a silent
/// empty gist.
final class GistDeriver {
  const GistDeriver(this._llm);

  final GistLlm _llm;

  /// The gist for [body]. [manualGist], when given, is returned verbatim and
  /// the seam is never called. Otherwise the seam derives the line; a thrown
  /// seam or an empty answer raises [GistDerivationFailed].
  Future<String> derive(String body, {String? manualGist}) async {
    if (manualGist != null) return manualGist;

    final String raw;
    try {
      raw = await _llm(body);
    } on Exception catch (e) {
      throw GistDerivationFailed('$e');
    }

    final line = raw.trim().split('\n').first.trim();
    if (line.isEmpty) throw const GistDerivationFailed('the model returned no gist');
    return line;
  }
}

/// Raised when gist derivation cannot produce a line — the seam threw or came
/// back empty. Surfaces so the caller refuses the write instead of landing a
/// blank gist.
final class GistDerivationFailed implements Exception {
  const GistDerivationFailed(this.detail);

  final String detail;

  @override
  String toString() => 'gist derivation failed: $detail';
}

const _gistSystem =
    'You write a single navigation line for a memory page: what a reader will '
    'find if they open it. One line only — no summary, no preamble, no quotes.';

/// The production [GistLlm]: pipe [body] to the `llm` coreutil under the gist
/// system prompt and read back its single line. A non-zero exit surfaces as
/// [GistDerivationFailed].
Future<String> llmGist(String body) async {
  final proc = await io.Process.start('llm', const ['-s', _gistSystem]);
  proc.stdin.write(body);
  await proc.stdin.close();
  final out = await proc.stdout.transform(utf8.decoder).join();
  final code = await proc.exitCode;
  if (code != 0) {
    final err = await proc.stderr.transform(utf8.decoder).join();
    throw GistDerivationFailed('llm exited $code: ${err.trim()}');
  }
  return out;
}
