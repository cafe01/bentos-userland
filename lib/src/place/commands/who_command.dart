import 'package:args/command_runner.dart';

import '../place_runner.dart';
import '../render/who_render.dart';

/// `place who [path]` — presence: the entity namespaces anchored at a place
/// (default: current). `-a`/`--all` climbs the ancestors.
final class WhoCommand extends Command<void> {
  WhoCommand(this._runner) {
    argParser.addFlag('all',
        abbr: 'a',
        negatable: false,
        help: 'Include ancestor-inherited inhabitants, each tagged @place.');
  }

  final PlaceRunner _runner;

  @override
  String get name => 'who';

  @override
  String get description => 'The inhabitants of a place: the entity namespaces anchored here.';

  @override
  Future<void> run() async {
    final pathArg = argResults!.rest.isEmpty ? null : argResults!.rest.first;
    final place = _runner.placeAt(pathArg);
    final all = argResults!['all'] as bool;
    _runner.out.writeln(const WhoRender().render(place, all: all));
  }
}
