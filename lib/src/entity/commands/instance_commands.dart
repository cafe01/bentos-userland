import '../entity_runner.dart';
import '../../git/model/commit.dart';
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
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('new: <name> <instance> are required');
    final from = argResults!['from'] as String?;
    final born = cli
        .entityNamed(rest[0], place: placeOption)
        .instance(rest[1])
        .create(from: from == null ? null : Commit(from));
    cli.out.writeln(born.tip!.sha);
  }
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
  Future<void> run() async {
    final named = positional('name');
    for (final one in cli.entityNamed(named, place: placeOption).instances) {
      cli.out.writeln('${one.id}\t${one.tip?.sha ?? ''}');
    }
  }
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
  Future<void> run() async {
    for (final act in cli.instanceAt(coordinate(), place: placeOption).log) {
      cli.out.writeln(
        [
          act.commit.sha,
          act.name,
          act.actor.name,
          act.instant.toIso8601String(),
        ].join('\t'),
      );
    }
  }
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
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('show: <coord> <action> are required');
    final instance = cli.instanceAt(coordinate(), place: placeOption);
    // The second argument selects by object name, which is what a log line
    // hands back. An action's identity *is* its commit.
    final selected = instance.log.where((a) => a.commit.sha.startsWith(rest[1]));
    if (selected.isEmpty) {
      cli.err.writeln('entity show: no act ${rest[1]} of ${coordinate()}');
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    final act = selected.first;
    cli.out.writeln('action\t${act.name}');
    cli.out.writeln('actor\t${act.actor.name}');
    cli.out.writeln('parent\t${act.parent.sha}');
    for (final change in act.diff().changes) {
      cli.out.writeln('${change.kind.name}\t${change.path}');
    }
  }
}
