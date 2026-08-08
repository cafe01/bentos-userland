import 'package:args/command_runner.dart';

import '../gist_deriver.dart';
import '../mem_runner.dart';
import '../mem_store.dart';
import '../model/mem_page.dart';
import '../word_count.dart';
import 'reach.dart';

/// `mem gist <topic> | <selectors>` — re-derive the cue from the body already on
/// disk, in place. A metadata verb, shaped like `refocus`: the body is neither
/// read from stdin nor rewritten, `modified` does not move, and the only field
/// that changes is `gist`. `--set` writes the line by hand and skips the seam.
///
/// Why a verb rather than re-`remember`ing the page: `remember` requires the
/// body on stdin and stamps `modified`, which would make a corpus migration a
/// rewrite of every body through the shell.
///
/// A band run is one live model call per page, serially: the echo prints as each
/// page lands — not gathered at the end — so a stalled run is distinguishable
/// from a slow one from outside. One failure names its page and the rest of the
/// band continues.
final class GistCommand extends Command<void> {
  GistCommand(this._runner) {
    Reach.addOptions(argParser);
    argParser.addOption('set',
        help: 'Write this line verbatim instead of deriving it (single topic only).');
  }

  final MemRunner _runner;

  @override
  String get name => 'gist';

  @override
  String get description =>
      "Re-derive a page's gist from its body — never the body, never `modified`.";

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final manual = argResults!['set'] as String?;
    final topics = argResults!.rest;
    if (manual != null && topics.length != 1) {
      _fail('gist: --set takes exactly one <topic>.');
      return;
    }

    final selection = _select(store);
    if (selection.isEmpty) {
      _runner.announceBank(store.bank);
      _runner.out.writeln('gist: no pages matched — nothing to re-derive.');
      return;
    }

    _runner.announceBank(store.bank);

    final deriver = GistDeriver(_runner.gistLlm);
    const counter = WordCount();
    var derived = 0;
    var failed = 0;
    var before = 0;
    var after = 0;
    for (final page in selection) {
      // `regist` rewrites the whole file structurally, so a page with an
      // assumed type or attention would have that guess canonized into the
      // file the moment its gist is touched — the same laundering `remember`
      // and `refocus` refuse, reached here by a different door.
      if (page.isDegraded) {
        failed++;
        _runner.err.writeln(
          'mem: ${page.topic}: gist skipped — ${page.fields.assumptions.join('; ')}; '
          'repair with remember first.',
        );
        continue;
      }
      final String gist;
      try {
        gist = await deriver.derive(page.body, manualGist: manual);
      } on GistDerivationFailed catch (e) {
        failed++;
        _runner.err.writeln('mem: ${page.topic}: $e');
        continue;
      }
      store.registPage(page, gist);
      derived++;

      // The old text is what this verb deletes, so it is not printed: over a
      // band of fifty it makes the run unreadable. What is worth watching while
      // a corpus migrates is the shrink and the quality of what replaced it —
      // the measurement on the first row, the new cue alone on the second. The
      // two numbers also total into the band's before/after for free.
      final was = counter.count(page.fields.gist ?? '');
      final now = counter.count(gist);
      before += was;
      after += now;
      _runner.out
        ..writeln('gist  ${page.topic}  ${was}w → ${now}w')
        ..writeln('      $gist');
    }

    _runner.err.writeln(
      'mem: ${store.bank} · gist · $derived re-derived · $failed failed '
      '· ${before}w → ${after}w',
    );
    if (failed > 0) _runner.exitCode = 1;
  }

  /// Named topics win over the reach — the same resolution `refocus` uses, so
  /// the two metadata verbs select identically.
  List<MemPage> _select(MemStore store) {
    final cascade = store.cascade();
    final topics = argResults!.rest;
    if (topics.isNotEmpty) {
      final byTopic = {for (final p in cascade) p.topic: p};
      return [for (final t in topics) if (byTopic[t] != null) byTopic[t]!];
    }
    return Reach.from(argResults!).apply(cascade);
  }

  void _fail(String message) {
    _runner.err.writeln(message);
    _runner.exitCode = 1;
  }
}
