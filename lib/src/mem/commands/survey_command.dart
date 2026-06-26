import 'package:args/command_runner.dart';

import '../mem_runner.dart';
import '../model/mem_node.dart';
import '../render/survey_render.dart';

final class SurveyCommand extends Command<void> {
  SurveyCommand(this._runner) {
    argParser
      ..addOption('min-weight', help: 'Only pages at or above weight W (0.0–1.0).')
      ..addOption('max-weight', help: 'Only pages at or below weight W.')
      ..addOption('type', help: 'Only one mode: semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('tag', help: 'Only pages carrying TAG.')
      ..addOption('size-threshold', help: 'Word count above which the size hint [Nw] shows (default: 120).', defaultsTo: '120');
  }

  final MemRunner _runner;

  @override
  String get name => 'survey';

  @override
  String get description => 'Feel the shape of memory — the index, grouped by mode.';

  @override
  Future<void> run() async {
    final ctx = _runner.buildContext(globalResults!);
    if (ctx == null) return;

    final node = ctx.node;
    if (node == null) {
      ctx.out.write(ctx.surveyRender.renderBody([]));
      return;
    }

    final args = argResults!;
    final selected = ctx.pageSelector.select(
      node,
      minWeight: _parseDouble(args['min-weight'] as String?),
      maxWeight: _parseDouble(args['max-weight'] as String?),
      type: _parseType(args['type'] as String?),
      tag: args['tag'] as String?,
    );

    final bodies = <String, String>{};
    for (final page in selected) {
      final content = node.readContent(page);
      if (content != null) bodies[page.name] = content;
    }

    ctx.out.write(ctx.surveyRender.renderBody(selected, bodies: bodies));
    ctx.err.writeln(SurveyRender.kFooter);
  }

  static double? _parseDouble(String? s) => s == null ? null : double.tryParse(s);

  static MemPageType? _parseType(String? s) {
    if (s == null) return null;
    return MemPageType.values.where((t) => t.name == s).firstOrNull;
  }
}
