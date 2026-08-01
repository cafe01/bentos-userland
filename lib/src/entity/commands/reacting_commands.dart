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
  Future<void> run() => throw UnimplementedError('entity on');
}

/// `entity off <coord> <id>` — disarm one registration. Idempotent.
final class OffCommand extends EntityCommand {
  OffCommand(super.cli);

  @override
  String get name => 'off';

  @override
  String get description => 'Disarm a registration.';

  @override
  Future<void> run() => throw UnimplementedError('entity off');
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
  Future<void> run() => throw UnimplementedError('entity listeners');
}
