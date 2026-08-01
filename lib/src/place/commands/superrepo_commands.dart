import 'package:args/command_runner.dart';

import '../place_runner.dart';

/// The superrepo half of the coreutil: `ls`, `pin`, `timeline`.
///
/// **The upper block of `place` is spatial; this is the constellation.** These
/// verbs report and move what the place declares about what is installed in it
/// — names, origins, commits — and never look inside an entity. The organ reads
/// structure and never content, at both altitudes.
///
/// One line per fact, tab-separated, as the sisters print: a caller inside a
/// `$(...)` is the reader these are written for.

/// `place ls [path]` — what is installed here: name, origin, pin.
final class LsCommand extends Command<void> {
  LsCommand(this._runner);

  final PlaceRunner _runner;

  @override
  String get name => 'ls';

  @override
  String get description =>
      'What is installed in this place: name, origin, and the commit it is held at.';

  @override
  Future<void> run() async {
    final place = _runner.placeAt(
        argResults!.rest.isEmpty ? null : argResults!.rest.first);
    for (final record in place.installed) {
      // The pin may be empty — a place inside no repository, or an install
      // whose gitlink nobody has written. Printing the field regardless keeps
      // the shape one column count, which is what a cut(1) downstream needs.
      _runner.out.writeln('${record.name}\t${record.url}\t${record.sha}');
    }
  }
}

/// `place pin <name> [<sha>]` — read or set the commit this place holds true.
final class PinCommand extends Command<void> {
  PinCommand(this._runner);

  final PlaceRunner _runner;

  @override
  String get name => 'pin';

  @override
  String get description =>
      'Read or set the commit this place holds an installation at.';

  @override
  String get invocation => 'place pin <name> [<sha>]';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('a name is required');
    final place = _runner.placeAt(null);
    final name = rest.first;

    final record = place.lookup(name);
    if (record == null) {
      _runner.err.writeln('place: no installation named $name here');
      _runner.exitCode = 1;
      return;
    }

    if (rest.length == 1) {
      _runner.out.writeln(record.sha);
      return;
    }

    // Writing prints what it did, as the sisters do — and it prints the pin
    // read back from the substrate, never the argument handed in.
    place.pin(name, rest[1]);
    _runner.out.writeln(place.lookup(name)!.sha);
  }
}

/// `place timeline` — the WHEN of the space.
final class TimelineCommand extends Command<void> {
  TimelineCommand(this._runner);

  final PlaceRunner _runner;

  @override
  String get name => 'timeline';

  @override
  String get description =>
      'The timeline in view — a place\'s branch means time.';

  @override
  String get invocation => 'place timeline [ls]';

  @override
  Future<void> run() async {
    final place = _runner.placeAt(null);
    final rest = argResults!.rest;
    final current = place.timeline;

    if (rest.isEmpty) {
      if (current.isEmpty) {
        // No repository, or a detached head: both are *no timeline in view*,
        // and neither is an error — a place is allowed to stand outside time.
        _runner.err.writeln('place: no timeline in view here');
        return;
      }
      _runner.out.writeln(current);
      return;
    }

    if (rest.first != 'ls') usageException('unknown timeline verb: ${rest.first}');
    for (final name in place.timelines) {
      _runner.out.writeln('${name == current ? '*' : ' '}\t$name');
    }
  }
}
