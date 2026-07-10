import 'package:args/command_runner.dart';

import '../place_runner.dart';
import '../render/tree_render.dart';

/// `place tree [path]` — the full recursive listing from a place (default:
/// current), everything expanded. `-t` drops descriptions for token-tight
/// contexts.
final class TreeCommand extends Command<void> {
  TreeCommand(this._runner) {
    argParser.addFlag('topology-only',
        abbr: 't',
        negatable: false,
        help: 'Paths only; drop descriptions (for token-tight contexts).');
  }

  final PlaceRunner _runner;

  @override
  String get name => 'tree';

  @override
  String get description =>
      'Full recursive listing from a place (default: current), everything expanded.';

  @override
  Future<void> run() async {
    final pathArg = argResults!.rest.isEmpty ? null : argResults!.rest.first;
    final place = _runner.placeAt(pathArg);
    final node = _runner.indexUnder(place).nodeFor(place);
    if (node == null) {
      _runner.err.writeln('place tree: ${place.root.path} is not in the habitat.');
      _runner.exitCode = 1;
      return;
    }
    final topologyOnly = argResults!['topology-only'] as bool;
    _runner.out.writeln(TreeRender(topologyOnly: topologyOnly).render(node));
  }
}
