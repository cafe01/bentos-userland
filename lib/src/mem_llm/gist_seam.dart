import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../mem/writer.dart';

/// The production [GistSource]: pipe a page's body to the `llm` coreutil
/// under the gist system prompt and read back its single line. Never throws
/// — a failed or stalled call returns `null`, which [Writer] reads as an
/// ordinary refusal (R8: the tool must hold with no model available).
final class LlmGistSource implements GistSource {
  const LlmGistSource({this.timeout = const Duration(seconds: 60)});

  final Duration timeout;

  @override
  Future<String?> derive(String body) async {
    final io.Process proc;
    try {
      proc = await io.Process.start('llm', const ['-s', _gistSystem]);
    } on Object {
      return null;
    }
    proc.stdin.write(body);
    await proc.stdin.close();

    // Read through cancellable subscriptions, never `asFuture`: on timeout the
    // child's own output stream may be held open by something it spawned, and
    // a pending join would keep this process alive forever.
    final out = _Pipe(proc.stdout);
    final err = _Pipe(proc.stderr);

    final int code;
    try {
      code = await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill(io.ProcessSignal.sigkill);
      await out.abandon();
      await err.abandon();
      return null;
    }
    await out.done;
    await err.done;
    if (code != 0) return null;

    final line = out.text.trim().split('\n').first.trim();
    return line.isEmpty ? null : line;
  }
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
