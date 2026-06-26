import 'package:args/command_runner.dart';

final class RecallCommand extends Command<void> {
  RecallCommand() {
    argParser
      ..addOption('min-weight', help: 'Pages at or above weight W (0.0–1.0).')
      ..addOption('max-weight', help: 'Pages at or below weight W.')
      ..addOption('type', help: 'One mode: semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('tag', help: 'Pages carrying TAG.');
  }

  @override
  String get name => 'recall';

  @override
  String get description => 'Bring page(s) into the frame, in full — pure retrieval.';

  @override
  Future<void> run() async {
    throw UnimplementedError('recall not yet implemented');
  }
}
