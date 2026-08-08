import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

/// The llm seam: a page body in, its one-line cue out. Injected so tests stub
/// it and never reach a live model.
typedef GistLlm = Future<String> Function(String body);

/// Derives a page's gist — the **cue**: the one line an index prints in place
/// of the page, so its owner can decide which page to open now.
///
/// The artifact is a cue and explicitly not a stand-in for the page: a reader
/// who could act on the line without opening the page was given too much, and
/// that is the failure the prompt spends most of its words on. The index is the
/// second-heaviest block in a staged mind and it grows with the bank forever,
/// so every word here is paid at every waking.
///
/// A manual gist wins and skips the seam entirely. A derivation that yields
/// nothing surfaces as [GistDerivationFailed]: the organ never writes a silent
/// empty gist.
final class GistDeriver {
  const GistDeriver(this._llm);

  final GistLlm _llm;

  /// The cue for [body]. [manualGist], when given, is returned verbatim and the
  /// seam is never called — a hand-written line is the author's own judgement
  /// about what triggers the reach, and outranks the model's. Otherwise the seam
  /// derives it; a thrown seam or an empty answer raises [GistDerivationFailed].
  ///
  /// No length is enforced here. Length is proportional to substance and a cap
  /// would truncate a genuinely multi-subject page mid-claim: the discipline
  /// lives in the prompt, and whether it held is measured over the corpus.
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
You write the cue for a memory page: the one line an index prints in place of the page, for the person whose memory this is.

The cue exists to trigger a reach. Its reader is scanning their own map to decide WHICH page to open now — so the line must make that decision possible, and must not make it unnecessary.

- Name what the page is, in the page's own vocabulary, then give the ONE OR TWO SHARPEST CONCRETE THINGS IT ASSERTS — in the page's own nouns, not the category they belong to. "a moving worktree is not a heartbeat; a static gauge is the real evidence" is a cue. "determining whether work is occurring through indirect readings" is the same sentence with the knowledge removed.
- Write a sentence about the SUBJECT, never an inventory of nouns. A line that reads as a comma-separated list of topics has failed, however accurate every item in it is.
- NEVER DESCRIBE THE PAGE'S ASSERTIONS IN THE ABSTRACT. Banned outright: "claims about", "principles", "dynamics", "implications", "considerations", "nuances", "mechanisms of", "the interplay of", "the nature of", "aspects", "factors". Each of these names a category where the page named a thing; a line built from them would fit any page on the subject and therefore identifies none.
- A page's headings, its links and the values it enumerates are its STRUCTURE, never its substance. Never build the line out of the table of contents: "create, install, publish, remotes, ls, log, show" tells a reader nothing the title did not. The same holds for the names of neighbouring pages — what a page links to is not what it is about.
- Where the subject is a surface — an API, a command, a schema — say what the surface is for and what is distinctive about its shape. Never list its members.
- A reader who could act on your line without opening the page has been given too much. That is the opposite failure and it is equally easy to commit.
- Never write ABOUT the page: no "this page", "covers", "explores", "outlines", "a discussion of".
- Length follows substance, never a quota: a page carrying one law needs a handful of words, a page carrying several must say so. Most pages land near 20 words and few need more than 40. Do not pad a thin page to look substantial.
- Never invent, and never reach a verdict the page does not: a page stating a conception is not reported as a list of failures.
- Output the line and nothing else: no preamble, no quotes, no markdown.

Shape: <what it is> — <its sharpest one or two assertions, concretely>.''';

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
