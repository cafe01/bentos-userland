import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_page.dart';
import '../relative_age.dart';
import '../render/recall_render.dart';
import '../word_count.dart';
import 'reach.dart';

/// `mem recall` — deliberate retrieval, full bodies. Pick by topic (the
/// deliberate grab) or by predicate (the band pull, e.g. the wake trust-read
/// `recall --hot`). A multi-topic recall is atomic: every named topic must
/// resolve or the whole read fails, naming the missing and printing nothing.
final class RecallCommand extends Command<void> {
  RecallCommand(this._runner) {
    Reach.addOptions(argParser);
  }

  final MemRunner _runner;

  @override
  String get name => 'recall';

  @override
  String get description =>
      'Bring page(s) into the frame, in full — by topic or by predicate.';

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final topics = argResults!.rest;
    final cascade = store.cascade();

    // Said before anything else: a topic that failed to parse is absent from the
    // cascade, so without this line the next branch would call it unknown — the
    // one wrong answer, since the page is right there and merely unreadable.
    for (final d in store.damage) {
      _runner.err.writeln(d.describe());
    }

    final List<MemPage> pages;
    if (topics.isNotEmpty) {
      final byTopic = {for (final p in cascade) p.topic: p};
      final missing = topics.where((t) => !byTopic.containsKey(t)).toList();
      if (missing.isNotEmpty) {
        _runner.err.writeln('mem: unknown topic(s): ${missing.join(', ')}');
        _runner.exitCode = 1;
        return;
      }
      pages = [for (final t in topics) byTopic[t]!];
    } else {
      pages = Reach.from(argResults!).apply(cascade);
    }

    _runner.announceBank(store.bank);
    _runner.out.write(RecallRender(RelativeAge(_runner.clock)).render(pages));

    // A band pull reports its own weight — on stderr, so the total never enters
    // the stdout that becomes a mind. This is the one place that counts: callers
    // staging a band (claude-spawn) echo this line instead of measuring the
    // string themselves, which is how a character count once masqueraded as `k`.
    // The bank rides along because `announceBank` speaks on stdout: a total that
    // reaches the caller alone must carry what it is a total *of*.
    if (pages.length > 1) {
      const counter = WordCount();
      final total = pages.fold(0, (n, p) => n + counter.count(p.body));
      _runner.err.writeln(
        'mem: ${store.bank} · recall · ${pages.length} pages · $total words',
      );
    }
  }
}
