import 'package:args/command_runner.dart';

import '../place_init.dart';
import '../place_runner.dart';

/// `place init [path]` — promote a folder (default: current) to a place by
/// creating `.place/` and writing `.place/place.yaml`.
final class InitCommand extends Command<void> {
  InitCommand(this._runner) {
    argParser
      ..addOption('name', abbr: 'n', help: 'Place name (default: directory name).')
      ..addOption('owner', abbr: 'o', help: 'Owning agent.')
      ..addOption('desc', abbr: 'd', help: 'One-line description.');
  }

  final PlaceRunner _runner;

  @override
  String get name => 'init';

  @override
  String get description => 'Promote a folder to a place by creating .place/.';

  @override
  Future<void> run() async {
    final pathArg = argResults!.rest.isEmpty ? _runner.cwd : argResults!.rest.first;
    final result = PlaceInit(_runner.fs).run(
      pathArg,
      name: argResults!['name'] as String?,
      owner: argResults!['owner'] as String?,
      desc: argResults!['desc'] as String?,
    );
    _runner.out.writeln(result.message);
    if (!result.created) _runner.exitCode = 1;
  }
}
