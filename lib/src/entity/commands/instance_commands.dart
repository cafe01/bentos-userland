import 'entity_command.dart';

/// `entity new <name> <instance> [--from <ref>]` — the constructor.
///
/// An instance is born from a commit, always: genesis by default, a live commit
/// for a fork. One operation, two origins, and which it was stays legible in
/// the history rather than in a second verb.
///
/// `new` is a reserved word in Dart, so the library spells the constructor
/// otherwise; at a shell it is simply the right word, and there are no handles
/// here to distinguish from births — every line typed is an act.
final class NewCommand extends EntityCommand {
  NewCommand(super.cli) {
    argParser.addOption(
      'from',
      help: 'Birth it from this commit — a fork. Genesis by default.',
      valueHelp: 'ref',
    );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Birth an instance — genesis by default.';

  @override
  Future<void> run() => throw UnimplementedError('entity new');
}

/// `entity ls <name>` — the instances. **Genesis is not one of them**: it is
/// the structure they are born from.
final class LsCommand extends EntityCommand {
  LsCommand(super.cli);

  @override
  String get name => 'ls';

  @override
  String get description => 'The instances — genesis is not one.';

  @override
  Future<void> run() => throw UnimplementedError('entity ls');
}

/// `entity log <coord>` — the acts.
///
/// Reading an instance's events in sequence *is* reading its log under another
/// name, which is why an actor's context comes free with the medium.
final class LogCommand extends EntityCommand {
  LogCommand(super.cli);

  @override
  String get name => 'log';

  @override
  String get description => 'The acts taken on an instance.';

  @override
  Future<void> run() => throw UnimplementedError('entity log');
}

/// `entity show <coord> <action>` — what one act changed. Derived on demand:
/// the substrate stores whole states and never differences.
final class ShowCommand extends EntityCommand {
  ShowCommand(super.cli);

  @override
  String get name => 'show';

  @override
  String get description => 'What one act changed.';

  @override
  Future<void> run() => throw UnimplementedError('entity show');
}
