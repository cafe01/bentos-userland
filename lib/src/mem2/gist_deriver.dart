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

const _gistSystem = r'''
You write the gist of a memory page: the one line that stands in place of the page for a reader who does not open it.

That reader is the person whose memory this is, scanning an index of their own knowledge to decide what to recall now. The line must carry the page's substance — never a description of the page.

- State the page's own claims, in the page's own vocabulary and language. Never write ABOUT the page: no "this page", no "an exploration of", "a discussion of", "covers", "explores", "details", "outlines", "delves into".
- Open with what the subject IS in a few words, then its load-bearing claims — the laws, distinctions, consequences, pathologies and exceptions a reader would be wrong not to know. If the page leaves a question open, say so: that is often why someone returns to it.
- One line does not mean short. It is one line because the index prints one line per page — length is set by how much the page actually claims, and 40–80 words is ordinary. Spend every word on a claim: join them with semicolons and dashes rather than connectives, and cut adjectives that carry no fact. Leaving out a load-bearing claim to stay brief is the worst failure of all.
- Never invent. Every claim in the line must be on the page, in the page's own terms.
- Prefer the page's concrete nouns to abstract paraphrase. "the client reaches the firm only through a chief" beats "a structured boundary is maintained with external parties". A line that would fit fifty other pages has failed.
- Output the line and nothing else: no preamble, no quotes, no markdown, no trailing commentary.

Shape: <what it is> — <the claims that matter>; <the distinction, consequence or open question someone who skipped the page would get wrong>.''';

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
