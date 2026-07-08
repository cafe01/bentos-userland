import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../place.dart';
import '../place_runner.dart';

/// `place init [path]` — promote a folder (default: current) to a place by
/// creating `.place/` and writing `.place/place.yaml`. A pre-existing place is
/// reported cleanly, never clobbered.
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
    final abs = p.isAbsolute(pathArg) ? pathArg : p.join(_runner.cwd, pathArg);
    final anchor = p.normalize(abs);
    final label = p.basename(anchor).isEmpty ? anchor : p.basename(anchor);

    final probe = Place(anchor);
    final alreadyAPlace = !probe.isImplicit && probe.root.path == anchor;
    if (alreadyAPlace) {
      _runner.out.writeln('place already initialized  $label  →  $anchor');
      _runner.exitCode = 1;
      return;
    }

    final owner = argResults!['owner'] as String?;
    probe.create(
      name: argResults!['name'] as String?,
      owner: owner,
      description: argResults!['desc'] as String?,
    );
    final ownerNote = owner == null ? '' : '  (owner: $owner)';
    _runner.out.writeln('initialized place  $label$ownerNote  →  $anchor');
  }
}
