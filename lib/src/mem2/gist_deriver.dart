import 'dart:async';
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
    } on GistDerivationFailed {
      rethrow; // already the caller-facing message; never wrap it twice
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

/// How long the seam waits on `llm` before giving up. The derivation is a live
/// model call over the network with nothing else bounding it, so a stalled
/// request would otherwise hang the write forever.
const gistTimeout = Duration(seconds: 60);

/// The production [GistLlm]: pipe [body] to the `llm` coreutil under the gist
/// system prompt and read back its single line. A non-zero exit surfaces as
/// [GistDerivationFailed]; so does a call that outruns [gistTimeout], with the
/// child killed rather than left running. The write is refused either way —
/// nothing is lost, since the body still sits in `--file` or the caller's hand.
Future<String> llmGist(String body, {Duration timeout = gistTimeout}) async {
  final proc = await io.Process.start('llm', const ['-s', _gistSystem]);
  proc.stdin.write(body);
  await proc.stdin.close();
  // The pipes are read through cancellable subscriptions rather than joined:
  // on timeout the child's output stream may be held open by something it
  // spawned, and a pending join would keep this process alive forever — the
  // hang moved one level down instead of being cured. Completion is tracked
  // with a Completer and never with `asFuture`, though: the pipe
  // is usually done before the exit code is awaited, and `asFuture` on a
  // subscription whose `done` already fired never completes — which drains the
  // event loop and lets the VM exit 0 with the write unmade.
  final out = _Pipe(proc.stdout);
  final err = _Pipe(proc.stderr);

  final int code;
  try {
    code = await proc.exitCode.timeout(timeout);
  } on TimeoutException {
    proc.kill(io.ProcessSignal.sigkill);
    await out.abandon();
    await err.abandon();
    throw GistDerivationFailed(
      'llm did not answer within ${timeout.inSeconds}s — '
      'retry, or write the line yourself with --gist "..."',
    );
  }
  await out.done;
  await err.done;
  if (code != 0) {
    throw GistDerivationFailed('llm exited $code: ${err.text.trim()}');
  }
  return out.text;
}

/// One of the child's output pipes, accumulated through a cancellable
/// subscription. [done] completes when the stream ends or errors; [abandon]
/// drops the pipe when the child is killed, so nothing pending can keep this
/// process alive past the kill.
final class _Pipe {
  _Pipe(Stream<List<int>> stream) {
    _sub = stream.transform(utf8.decoder).listen(
      _buffer.write,
      onDone: _finish,
      onError: (Object _) => _finish(),
      cancelOnError: true,
    );
  }

  final StringBuffer _buffer = StringBuffer();
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<String> _sub;

  Future<void> get done => _done.future;
  String get text => _buffer.toString();

  Future<void> abandon() async {
    await _sub.cancel();
    _finish();
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }
}
