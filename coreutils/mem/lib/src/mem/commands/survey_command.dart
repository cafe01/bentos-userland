import 'package:args/command_runner.dart';

final class SurveyCommand extends Command<void> {
  SurveyCommand() {
    argParser
      ..addOption('min-weight', help: 'Only pages at or above weight W (0.0–1.0).')
      ..addOption('max-weight', help: 'Only pages at or below weight W.')
      ..addOption('type', help: 'Only one mode: semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('tag', help: 'Only pages carrying TAG.')
      ..addOption('size-threshold', help: 'Word count above which the size hint [Nw] shows (default: 120).', defaultsTo: '120');
  }

  @override
  String get name => 'survey';

  @override
  String get description => 'Feel the shape of memory — the index, grouped by mode.';

  @override
  Future<void> run() async {
    throw UnimplementedError('survey not yet implemented');
  }
}
