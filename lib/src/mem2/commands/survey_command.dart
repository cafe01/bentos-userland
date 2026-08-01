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
    argParser.addOption('size-threshold',
        defaultsTo: '120',
        help: 'Words above which the [Nw] size hint shows (default: 120).');
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
    final selected = reach.apply(cascade);

    _runner.announceBank(store.bank);

    for (final d in store.damage) {
      _runner.err.writeln(d.describe());
    }

    // Nothing selected is an answer, not a failure: a reach that matches no page
    // has told the caller what it asked. Only the two cases differ in what is
    // worth saying — an untouched bank gets the begin-one nudge, a reach that
    // found nothing gets the reach echoed back.
    if (selected.isEmpty) {
      _runner.err.writeln(
        cascade.isEmpty
            ? SurveyRender.emptyGuidance
            : SurveyRender.noMatch(reach.describe()),
      );
      return;
    }

    final render = SurveyRender(
      age: RelativeAge(_runner.clock),
      wordCount: WordCount(threshold: int.parse(argResults!['size-threshold'] as String)),
    );
    _runner.out.writeln(render.render(selected, vantage: store.vantage));

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
      'mem: ${store.bank} · survey · ${selected.length} pages · $total words',
    );
  }
}
