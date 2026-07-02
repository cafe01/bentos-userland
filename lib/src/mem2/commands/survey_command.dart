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

    final selected = Reach.from(argResults!).apply(store.cascade());
    if (selected.isEmpty) {
      _runner.err.writeln(SurveyRender.emptyGuidance);
      _runner.exitCode = 1;
      return;
    }

    final render = SurveyRender(
      age: RelativeAge(_runner.clock),
      wordCount: WordCount(threshold: int.parse(argResults!['size-threshold'] as String)),
    );
    _runner.out.writeln(render.render(selected, vantage: store.vantage));
  }
}
