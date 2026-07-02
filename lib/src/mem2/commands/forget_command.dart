import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_page.dart';
import '../write_echo.dart';

/// `mem forget <topic>…` — release pages and delete their content. Variadic and
/// atomic: every named topic must resolve before anything is deleted; one
/// unknown fails the whole call, naming the missing, deleting nothing. Topic-only
/// — a predicate selector is refused, because mass deletion by band or tag is a
/// gesture the organ does not offer.
final class ForgetCommand extends Command<void> {
  ForgetCommand(this._runner);

  final MemRunner _runner;

  @override
  String get name => 'forget';

  @override
  String get description => 'Remove the named page(s) and delete their content — by name only.';

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final topics = argResults!.rest;
    if (topics.isEmpty) {
      _runner.err.writeln('mem: forget takes one or more <topic> — deletion is by name only.');
      _runner.exitCode = 1;
      return;
    }

    final byTopic = {for (final p in store.cascade()) p.topic: p};
    final missing = topics.where((t) => !byTopic.containsKey(t)).toList();
    if (missing.isNotEmpty) {
      _runner.err.writeln('mem: unknown topic(s): ${missing.join(', ')} — nothing deleted.');
      _runner.exitCode = 1;
      return;
    }

    final pages = <MemPage>[for (final t in topics) byTopic[t]!];
    for (final page in pages) {
      store.deletePage(page);
    }
    _runner.out.writeln(WriteEcho(store.vantage).forgot(pages));
  }
}
