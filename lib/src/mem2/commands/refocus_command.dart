import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../mem_store.dart';
import '../model/attention.dart';
import '../model/mem_page.dart';
import '../write_echo.dart';
import 'reach.dart';

/// `mem refocus <selector> --to A | --by ±D` — move attention, never the body.
/// Bulk by default (the reach the read verbs use) and relative when asked;
/// `--by` clamps at the rails and the echo marks it. An inherited page
/// refocuses where it lives; an empty selection is a clean no-op, not an error.
final class RefocusCommand extends Command<void> {
  RefocusCommand(this._runner) {
    Reach.addOptions(argParser);
    argParser
      ..addOption('to', help: 'Set every selected page to attention A (absolute).')
      ..addOption('by', help: 'Shift every selected page by ±D (relative, clamps at the rails).');
  }

  final MemRunner _runner;

  @override
  String get name => 'refocus';

  @override
  String get description => 'Move the attention of one or many pages — never the body.';

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final to = argResults!['to'] as String?;
    final by = argResults!['by'] as String?;
    if ((to == null) == (by == null)) {
      _fail('refocus: pass exactly one of --to <attention> or --by <±delta>.');
      return;
    }

    final selection = _select(store);
    if (selection.isEmpty) {
      _runner.announceBank(store.bank);
      _runner.out.writeln('refocus: no pages matched — nothing to move.');
      return;
    }

    final List<RefocusChange> changes;
    try {
      changes = to != null ? _absolute(selection, to) : _relative(selection, by!);
    } on FormatException catch (e) {
      _fail('mem: $e');
      return;
    }

    for (final c in changes) {
      store.refocusPage(c.page, c.to);
    }
    _runner.announceBank(store.bank);
    _runner.out.writeln(
      WriteEcho(store.vantage).refocused(changes, selector: _selectorLabel(), by: by),
    );
  }

  List<MemPage> _select(MemStore store) {
    final cascade = store.cascade();
    final topics = argResults!.rest;
    if (topics.isNotEmpty) {
      final byTopic = {for (final p in cascade) p.topic: p};
      return [for (final t in topics) if (byTopic[t] != null) byTopic[t]!];
    }
    return Reach.from(argResults!).apply(cascade);
  }

  List<RefocusChange> _absolute(List<MemPage> pages, String to) {
    final target = Attention.parse(to);
    return [
      for (final p in pages) RefocusChange(p, p.fields.attention, target),
    ];
  }

  List<RefocusChange> _relative(List<MemPage> pages, String by) {
    final delta = Attention.parseDelta(by);
    // `--by` moves the *current* value, so an assumed base is a guess refined
    // by a guess — refuse it here and point at `--to`, which overwrites
    // cleanly regardless of what the prior value was.
    final assumed = pages.where(
      (p) => p.fields.assumptions.any((a) => a.field == 'attention' || a.field == 'frontmatter'),
    );
    if (assumed.isNotEmpty) {
      throw FormatException(
        'refocus --by cannot move an assumed attention '
        '(${assumed.map((p) => p.topic).join(', ')}) — the base was guessed, '
        'not read; use --to to set it explicitly instead.',
      );
    }
    return [
      for (final p in pages)
        () {
          final (next, clamped) = p.fields.attention.adjust(delta);
          return RefocusChange(p, p.fields.attention, next, clamped: clamped);
        }(),
    ];
  }

  String? _selectorLabel() {
    if (argResults!.rest.isNotEmpty) return null;
    final tag = argResults!['tag'] as String?;
    if (tag != null) return 'tag:$tag';
    final type = argResults!['type'] as String?;
    if (type != null) return 'type:$type';
    for (final band in ['hot', 'warm', 'cool', 'cold']) {
      if (argResults![band] == true) return band;
    }
    return 'attention range';
  }

  void _fail(String message) {
    _runner.err.writeln(message);
    _runner.exitCode = 1;
  }
}
