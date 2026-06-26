import 'package:args/command_runner.dart';

final class RememberCommand extends Command<void> {
  RememberCommand() {
    argParser
      ..addOption('type', abbr: 't', help: 'Memory mode. Required on create. semantic | procedural | episodic | prospective | autobiographical.')
      ..addOption('weight', abbr: 'W', help: 'Weight 0.0–1.0. Required on create.')
      ..addOption('telos', help: 'The page\'s contract — one short sentence: why it exists.')
      ..addOption('file', abbr: 'f', help: 'Read the body from PATH instead of stdin.')
      ..addOption('gist', help: 'Manual gist override.')
      ..addMultiOption('link', help: 'External destination. Repeatable; replaces the links list.')
      ..addMultiOption('tag', help: 'Associative tag. Repeatable; replaces the tags list.')
      ..addOption('scope', abbr: 's', help: 'Scope label (default: place directory name).');
  }

  @override
  String get name => 'remember';

  @override
  String get description => 'Create or replace a page, atomically. Body from stdin or --file.';

  @override
  Future<void> run() async {
    throw UnimplementedError('remember not yet implemented');
  }
}
