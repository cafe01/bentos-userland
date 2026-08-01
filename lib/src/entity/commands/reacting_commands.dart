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
final class OnCommand extends EntityCommand {
  OnCommand(super.cli);

  @override
  String get name => 'on';

  @override
  String get description => 'Arm a command on an entity\'s events.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('on: <coord> <event> are required');
    final woken = body();
    if (woken.isEmpty) {
      usageException('on: the command is required — `-- <command>`');
    }

    final coord = coordinate();
    final entity = cli.entityNamed(coord.entity, place: placeOption);
    // One line per pattern, and the id of each on its own line: `off` takes an
    // id, so arming three events and reporting one would leave two unreachable.
    for (final text in rest[1].split(',')) {
      final EventPattern pattern;
      try {
        pattern = EventPattern.parse(text.trim());
      } on FormatException catch (e) {
        usageException('on: ${e.message}');
      }
      final armed = entity.on(
        {pattern},
        command: woken,
        instance: coord.instance,
      );
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
      cli.out.writeln(
        [line.id, line.instance, '${line.pattern}', line.command.join(' ')]
            .join('\t'),
      );
    }
  }
}
