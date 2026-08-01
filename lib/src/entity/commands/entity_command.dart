import 'package:args/command_runner.dart';

import '../entity_runner.dart';
import 'coordinate.dart';

/// The base every `entity` verb stands on: the runner it writes through, and
/// the two argument readings the whole surface is built from — a bare name for
/// the class-level verbs, a coordinate for the instance-level ones.
abstract base class EntityCommand extends Command<void> {
  EntityCommand(this.cli);

  /// The coreutil this verb writes through. Named `cli` and not `runner`
  /// because `Command.runner` is the args package's own member, and shadowing
  /// it would be the surface fighting its host.
  final EntityRunner cli;

  /// The global `-C` as parsed by the runner's own parser.
  String? get placeOption => globalResults?['place'] as String?;

  /// The first positional, or a usage failure naming what was wanted.
  String positional(String label) {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('$name: <$label> is required');
    return rest.first;
  }

  /// The first positional read as a coordinate.
  Coordinate coordinate() {
    try {
      return Coordinate.parse(positional('coord'));
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }
  }
}
