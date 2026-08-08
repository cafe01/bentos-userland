import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../relative_age.dart';
import '../render/survey_render.dart';
import '../word_count.dart';
import 'reach.dart';

/// `mem survey` — the memory map. Cascades the vantage and its ancestors,
/// narrows by the shared reach, and renders the grouped index. A bare survey is
/// the whole map (0.0 included); an empty map is begin-one guidance, exit 1.
final class SurveyCommand extends Command<void> {
  SurveyCommand(this._runner) {
    Reach.addOptions(argParser);
    argParser
      ..addOption('size-threshold',
          defaultsTo: '120',
          help: 'Words above which the [Nw] size hint shows (default: 120).')
      ..addOption('limit',
          help: 'Render at most N pages, hottest first (default: unbounded).')
      ..addOption('offset',
          defaultsTo: '0',
          help: 'Skip the first N of the hottest-first order — the tail of a bounded map.');
  }

  final MemRunner _runner;

  @override
  String get name => 'survey';

  @override
  String get description =>
      'Survey the memory map — the index, grouped by mode, cascaded up the place tree.';

  @override
  Future<void> run() async {
    final store = _runner.buildStore(globalResults!);
    if (store == null) return;

    final cascade = store.cascade();
    final reach = Reach.from(argResults!);
    final matched = reach.apply(cascade);

    // select → sort → offset/limit → group (the render's own job). Hottest
    // first is what makes a bound meaningful: a map cut in composition order
    // would drop pages by mode and directory accident. The sort lives here and
    // not in PageSelector, whose contract is composition order and which recall
    // and refocus share.
    final int offset;
    final int? limit;
    try {
      offset = _bound('offset') ?? 0;
      limit = _bound('limit');
    } on FormatException catch (e) {
      _runner.err.writeln('mem: $e');
      _runner.exitCode = 1;
      return;
    }
    final ordered = [...matched]..sort((a, b) {
        final byAttention =
            b.fields.attention.tenths.compareTo(a.fields.attention.tenths);
        return byAttention != 0 ? byAttention : a.topic.compareTo(b.topic);
      });
    final windowed = ordered.skip(offset).toList();
    final selected =
        limit == null ? windowed : windowed.take(limit).toList();

    _runner.announceBank(store.bank);

    for (final d in store.damage) {
      _runner.err.writeln(d.describe());
    }
    for (final page in selected) {
      if (page.isDegraded) _runner.err.writeln(page.describeDegradation());
    }

    // Nothing selected is an answer, not a failure: a reach that matches no page
    // has told the caller what it asked. Only the two cases differ in what is
    // worth saying — an untouched bank gets the begin-one nudge, a reach that
    // found nothing gets the reach echoed back.
    if (selected.isEmpty) {
      // An offset past the end is neither an untouched bank nor an empty reach:
      // saying "no pages under --warm" there would be the map lying about the
      // bank instead of about the window.
      _runner.err.writeln(
        matched.isNotEmpty
            ? 'mem: offset $offset is past the end — ${matched.length} pages under ${reach.describe()}.'
            : cascade.isEmpty
                ? SurveyRender.emptyGuidance
                : SurveyRender.noMatch(reach.describe()),
      );
      return;
    }

    final render = SurveyRender(
      age: RelativeAge(_runner.clock),
      wordCount: WordCount(threshold: int.parse(argResults!['size-threshold'] as String)),
    );
    // The cut is printed inside the map, on stdout, and not only in the stderr
    // weight line: a mind staged with a bounded index must be able to see that
    // it was bounded, and how to ask for the rest. A map that lies about its own
    // completeness is worse than a heavy one — and the notice is also what keeps
    // a truncated mode group from reading as "these are all the procedural
    // pages", which is why it heads the map rather than trailing it.
    final cut = selected.length < matched.length;
    _runner.out.writeln(render.render(
      selected,
      vantage: store.vantage,
      notice: cut
          ? SurveyRender.truncation(
              from: offset + 1,
              to: offset + selected.length,
              total: matched.length,
            )
          : null,
    ));

    // The map reports its own weight, on stderr so the total never enters the
    // stdout that becomes a mind — the same contract the band pull keeps, and
    // for the same reason: a caller staging an index (claude-spawn) must be able
    // to see what it staged without measuring the string itself. The verb rides
    // along because the two registers weigh different things at the same bank:
    // recall counts bodies, survey counts the gists that stand in for them.
    const counter = WordCount();
    // Gists only — the body is precisely what a survey does not print, so
    // falling back to it for a gistless page would count words nobody was given.
    final total = selected.fold(
      0,
      (n, p) => n + counter.count(p.fields.gist ?? ''),
    );
    _runner.err.writeln(
      'mem: ${store.bank} · survey · ${selected.length} pages · $total words'
      '${cut ? ' (of ${matched.length})' : ''}',
    );
  }

  /// A bound, parsed. A non-number or a negative is refused rather than
  /// silently read as zero — a bound the caller believes it set and the organ
  /// ignored is the one failure a bound must not have.
  int? _bound(String name) {
    final raw = argResults![name] as String?;
    if (raw == null) return null;
    final n = int.tryParse(raw);
    if (n == null || n < 0) {
      throw FormatException('--$name takes a non-negative whole number, got "$raw"');
    }
    return n;
  }
}
