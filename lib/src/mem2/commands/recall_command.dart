import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_page.dart';
import '../relative_age.dart';
import '../render/recall_render.dart';
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
  }
}
