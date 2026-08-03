import 'package:args/command_runner.dart';

import '../entity_runner.dart';
import '../../git/model/commit.dart';
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

  /// The words after `--`: a program, and the second half of the two verbs
  /// that take one.
  ///
  /// Taken from the raw argument list rather than from `rest`, because the
  /// parser folds both sides of the separator into one list while the two
  /// halves mean different things — before it stand this verb's own
  /// positionals, after it stands somebody else's command line.
  List<String> body() {
    final raw = argResults!.arguments;
    final at = raw.indexOf('--');
    return at < 0 ? const [] : raw.sublist(at + 1);
  }

  /// The `--as-of <sha>` the reading verbs take, or null for the present tip.
  ///
  /// A point in history is a **named argument and never part of the
  /// coordinate**: `<coord>@<sha>:<path>` would put a fifth dimension into the
  /// address, and whether one belongs there is the ontology's question rather
  /// than this surface's.
  ///
  /// It is not a convenience either. A validator stands at the parent of the
  /// act landing and asks whether that act was legal *there*, which is never
  /// the present — so a surface that could only read the tip would push every
  /// historical reading back below the primitive.
  ///
  /// **Spelled `--as-of` because `--at` means *where* in this utility**, and it
  /// says so everywhere: `materialize --at <path>`, `refresh <coord> <path>`.
  /// One flag carrying two dimensions is a defect that only appears in the hand
  /// of whoever types it, which is the axis no assertion touches.
  Commit? pointInHistory() {
    final asOf = argResults!['as-of'] as String?;
    return asOf == null ? null : Commit(asOf);
  }

  /// Declares the point-in-history flag on a verb that reads.
  void takesPointInHistory() => argParser.addOption(
        'as-of',
        help: 'Read as the instance stood at this commit.',
        valueHelp: 'sha',
      );

  /// The first positional read as a coordinate.
  Coordinate coordinate() {
    try {
      return Coordinate.parse(positional('coord'));
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }
  }
}
