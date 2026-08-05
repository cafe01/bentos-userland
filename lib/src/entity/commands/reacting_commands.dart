import 'dart:io';

import 'package:path/path.dart' as p;

import '../arming/arming.dart';
import '../event.dart';
import 'entity_command.dart';

/// `entity on <coord> <event>[,<event>] -- <command>` — arm behaviour on what
/// an entity publishes.
///
/// This is how a stranger extends an entity it did not write: arm on its
/// events, act in your own. The phase in the pattern decides the power —
/// `.attempted` runs in line and may refuse, `.landed` is woken detached and
/// may act again.
///
/// Arming is per installation and never tracked, so what differs between two
/// deployments of one entity is one line in a table.
final class OnCommand extends ArmingCommand {
  OnCommand(super.cli);

  @override
  String get name => 'on';

  @override
  String get description => 'Arm a command on an entity\'s events.';

  @override
  bool get spent => false;
}

/// `entity once <coord> <event>[,<event>] -- <command>` — the same line with its
/// own removal attached: it fires, and it is gone.
///
/// **The only lifecycle the floor offers a subscriber.** Liveness, a pid, a
/// signal, a body that outlives its wake — all of that is the actor's own, and
/// nothing here holds a notion of a live one. This serves the caller that wants
/// exactly the next occurrence and nothing after it.
///
/// One line per event, so `once` on two events that fire once each fires twice.
/// Whoever wants them spent together is describing an actor.
final class OnceCommand extends ArmingCommand {
  OnceCommand(super.cli);

  @override
  String get name => 'once';

  @override
  String get description => 'Arm a command that fires once, then unregisters.';

  @override
  bool get spent => true;
}

/// What `on` and `once` share: everything but whether the line survives firing.
abstract base class ArmingCommand extends EntityCommand {
  ArmingCommand(super.cli);

  /// Whether the line removes itself when it fires.
  bool get spent;

  /// Refuses a relative command that will not resolve when the line fires.
  ///
  /// **The anchor of an armed command is the place the entity is installed in,
  /// never the directory the line was armed from.** A reaction is woken by the
  /// substrate long after the arming shell is gone, so `./reindex` typed in a
  /// subdirectory registers happily, lands nothing, and fires nothing — with no
  /// error anywhere, because by then there is nobody to tell. The check runs
  /// here for one reason: this is the last instant the person who typed it is
  /// still standing there.
  ///
  /// Only a path is judged. A bare name is the substrate's PATH to resolve at
  /// firing, and this process's PATH is not evidence about that one.
  void _refuseUnresolvableCommand(String command, String entity) {
    if (!command.contains('/') || command.startsWith('/')) return;

    final root = cli.installedAt(entity, place: placeOption).path;
    final resolved = p.normalize(p.join(root, command));
    if (File(resolved).existsSync()) return;

    usageException([
      '$name: "$command" is not there when the line fires',
      'an armed command is resolved against the place ($root), '
          'never against the directory you armed it from',
      'looked for: $resolved',
      'give an absolute path, or a path relative to the place',
    ].join('\n  '));
  }

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('$name: <coord> <event> are required');
    final woken = body();
    if (woken.isEmpty) {
      usageException('$name: the command is required — `-- <command>`');
    }
    // Refused here, at the terminal, rather than written to a table that cannot
    // hold it and firing something else weeks later.
    try {
      ArmingTables.checkCommand(woken);
    } on ArgumentError catch (e) {
      usageException('$name: ${e.message}');
    }

    final coord = coordinate();
    final entity = cli.entityNamed(coord.entity, place: placeOption);
    _refuseUnresolvableCommand(woken.first, coord.entity);
    // One line per pattern, and the id of each on its own line: `off` takes an
    // id, so arming three events and reporting one would leave two unreachable.
    for (final text in rest[1].split(',')) {
      final EventPattern pattern;
      try {
        pattern = EventPattern.parse(text.trim());
      } on FormatException catch (e) {
        usageException('$name: ${e.message}');
      }
      final armed = spent
          ? entity.once({pattern}, command: woken, instance: coord.instance)
          : entity.on({pattern}, command: woken, instance: coord.instance);
      cli.out.writeln(armed.id);
    }
  }
}

/// `entity off <coord> <id>` — disarm one registration. Idempotent.
final class OffCommand extends EntityCommand {
  OffCommand(super.cli);

  @override
  String get name => 'off';

  @override
  String get description => 'Disarm a registration.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('off: <coord> <id> are required');
    cli.entityNamed(coordinate().entity, place: placeOption).off(rest[1]);
  }
}

/// One armed argument as a person should read it: bare when it is one word,
/// single-quoted when it holds whitespace the display would otherwise erase.
String _shown(String argument) {
  if (argument.isEmpty) return "''";
  if (!argument.contains(RegExp(r'\s'))) return argument;
  return "'${argument.replaceAll("'", r"'\''")}'";
}

/// `entity listeners <coord>` — what is armed here. Here, and not anywhere
/// else: two installations of one entity are two participants, not two views.
final class ListenersCommand extends EntityCommand {
  ListenersCommand(super.cli);

  @override
  String get name => 'listeners';

  @override
  String get description => 'What is armed at this installation.';

  @override
  Future<void> run() async {
    final coord = coordinate();
    final armed = cli.entityNamed(coord.entity, place: placeOption).listeners;
    for (final line in armed) {
      // A coordinate naming one instance asks what would wake for *that*
      // object, which includes everything armed across the class.
      if (coord.instance != '*' &&
          line.instance != '*' &&
          line.instance != coord.instance) {
        continue;
      }
      // The lifetime is printed because a line that will disappear on its next
      // firing is not the same fact as one that will not, and a table read as
      // if it were would be the graph lying about itself.
      cli.out.writeln(
        [
          line.id,
          line.instance,
          '${line.pattern}',
          line.once ? ArmingTables.onceLifetime : ArmingTables.alwaysLifetime,
          // Quoted where a bare word would lie: this column is read by a person
          // deciding whether the armed line is the one they meant, and a command
          // printed as `sh -c echo hi` claims boundaries the line does not have.
          line.command.map(_shown).join(' '),
        ].join('\t'),
      );
    }
  }
}
