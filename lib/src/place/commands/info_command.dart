import 'package:args/command_runner.dart';

import '../place_runner.dart';
import '../render/info_render.dart';

/// `place info [path]` — the metadata card of a single place (default: current):
/// name, description, owner.
final class InfoCommand extends Command<void> {
  InfoCommand(this._runner);

  final PlaceRunner _runner;

  @override
  String get name => 'info';

  @override
  String get description => 'The metadata card of a single place: name, description, owner.';

  @override
  Future<void> run() async {
    final pathArg = argResults!.rest.isEmpty ? null : argResults!.rest.first;
    final place = _runner.placeAt(pathArg);
    if (place.metaWarning != null) {
      _runner.err.writeln('place info: ${place.metaWarning}');
    }
    _runner.out.writeln(const InfoRender().render(place));
  }
}
