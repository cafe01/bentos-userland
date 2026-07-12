import 'package:args/command_runner.dart';

import '../minimap.dart';
import '../place_runner.dart';
import '../render/minimap_render.dart';

/// `place where` — the "you are here" minimap: the whole habitat, your location
/// marked, detail decaying with distance (the fog).
final class WhereCommand extends Command<void> {
  WhereCommand(this._runner) {
    argParser.addOption('radius',
        abbr: 'r',
        defaultsTo: '1',
        help: 'How many place-hops around you stay fully expanded (default: 1).');
  }

  final PlaceRunner _runner;

  @override
  String get name => 'where';

  @override
  String get description =>
      'The "you are here" minimap — the whole habitat, your location marked.';

  @override
  Future<void> run() async {
    final radius = int.tryParse(argResults!['radius'] as String);
    if (radius == null || radius < 0) {
      _runner.err.writeln('place where: --radius must be a non-negative integer.');
      _runner.exitCode = 1;
      return;
    }
    final current = _runner.placeAt(null);
    final map = Minimap(radius: radius).build(_runner.neighborhood(current), current);
    _runner.out.writeln(const MinimapRender().render(map));
  }
}
