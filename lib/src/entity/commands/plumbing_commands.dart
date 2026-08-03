import 'dart:io';

import '../entity.dart';
import '../entity_runner.dart';
import '../../git/git_ambient.dart';
import '../../git/model/actor.dart';
import '../../git/model/commit.dart';
import '../workspace.dart';
import 'entity_command.dart';

/// The plumbing family exists for what does not fit the bracket, and **it is
/// the family that matters most: the callers here are programs.**
///
/// `work` and `commit` are also the one shape a callback cannot serve — three
/// separate processes, no closure spanning them — which is why the pieces
/// survive at the shell after the library made the bracket its only safe path.

/// `entity resolve <coord>` → path.
///
/// The selection turned into somewhere to stand: the entity's own directory in
/// the place that answers for it. A coordinate is a selection and never a
/// runtime address — coordinate resolves, path operates — and this is the verb
/// that crosses between the two.
final class ResolveCommand extends EntityCommand {
  ResolveCommand(super.cli);

  @override
  String get name => 'resolve';

  @override
  String get description => 'Resolve a coordinate to a path.';

  @override
  Future<void> run() async {
    final coord = coordinate();
    final place = cli.installedAt(coord.entity, place: placeOption);
    cli.out.writeln('${place.path}/${coord.entity}');
  }
}

/// `entity tip <coord>` → sha. What an actor reads before it works, and hands
/// back as the value the swap must find.
final class TipCommand extends EntityCommand {
  TipCommand(super.cli);

  @override
  String get name => 'tip';

  @override
  String get description => 'The commit an instance stands at.';

  @override
  Future<void> run() async {
    final coord = coordinate();
    final at = cli.instanceAt(coord, place: placeOption).tip;
    if (at == null) {
      // Null is the honest reading of a ref that does not exist, and it is the
      // same answer the swap takes to mean *must not exist*.
      cli.err.writeln('entity tip: not born: $coord');
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    cli.out.writeln(at.sha);
  }
}

/// `entity path <name>` → the entity's own repository — **the escape hatch**.
///
/// The library refuses this deliberately: a caller holding a repository runs
/// Git itself, below the ontology and past the swap. Here it stands as a named
/// verb, so that going below is a decision a person takes visibly rather than
/// something a consumer stumbles into.
final class PathCommand extends EntityCommand {
  PathCommand(super.cli);

  @override
  String get name => 'path';

  @override
  String get description => 'The entity\'s own repository — the escape hatch.';

  @override
  Future<void> run() async {
    final named = positional('name');
    cli.out.writeln(gitDirOf(cli.entityNamed(named, place: placeOption)));
  }
}

/// `entity work <coord>` → a private materialization, with the obligation
/// attached.
///
/// The compare-and-swap protects the ref and nothing inside a directory: two
/// bodies writing into one shared worktree corrupt each other before either
/// reaches the swap, and both then land honestly. So the primitive owes the
/// area, and whoever opens one owes `commit` and `release`.
final class WorkCommand extends EntityCommand {
  WorkCommand(super.cli);

  @override
  String get name => 'work';

  @override
  String get description => 'Open a private write area at the tip.';

  @override
  Future<void> run() async {
    final opened = cli.instanceAt(coordinate(), place: placeOption).beginAct();
    // Both halves on one line, because a workspace *is* the pair: the area to
    // write in, and the value the swap will demand the ref still holds. A
    // caller that had to fetch the tip separately could be handed one taken a
    // moment after the area was cut, and would then swap against a state its
    // own files were never based on.
    cli.out.writeln('${opened.directory.path}\t${opened.expectedTip.sha}');
  }
}

/// `entity commit <coord> <action> -w <path> --parent <sha> [--actor <a>] [--say <phrase>]`
/// — close an act opened by `work`.
///
/// `--parent` is the whole reason the last step is plumbing: ordinary Git
/// commits onto whatever tip it finds when it runs, and an act must instead
/// name the value the ref is required to still hold.
///
/// The coordinate is named here and nowhere in the spec's shorter form,
/// because a workspace does not survive a process: `work`, `commit` and
/// `release` are three of them, and the ref an act lands on is the one fact a
/// detached directory cannot report about itself.
final class CommitCommand extends EntityCommand {
  CommitCommand(super.cli) {
    argParser
      ..addOption('worktree', abbr: 'w', help: 'The area opened by `work`.')
      ..addOption('parent', help: 'The value the ref must still hold.')
      ..addOption('actor', help: 'The identity written as the author.')
      ..addOption(
        'say',
        help: 'The legible sentence, stored and never interpreted.',
        valueHelp: 'phrase',
      );
  }

  @override
  String get name => 'commit';

  @override
  String get description => 'Land an act from a private area, by compare-and-swap.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('commit: <coord> <action> are required');
    final area = argResults!['worktree'] as String?;
    if (area == null) usageException('commit: -w <path> is required');
    final parent = argResults!['parent'] as String?;
    if (parent == null) usageException('commit: --parent <sha> is required');

    final coord = coordinate();
    final instance = cli.instanceAt(coord, place: placeOption);
    final actor = argResults!['actor'] as String?;
    final workspace = Workspace(
      directory: Directory(cli.locate(area)),
      gitDir: gitDirOf(instance.entity),
      ref: instance.ref,
      expectedTip: Commit(parent),
    );
    cli.report(
      workspace.commit(
        rest[1],
        actor: actor == null ? null : Actor(actor),
        say: argResults!['say'] as String?,
      ),
    );
  }
}

/// `entity release <path>` — discard a workspace or a materialization.
/// Idempotent, because a caller that crashed may honestly run it twice.
final class ReleaseCommand extends EntityCommand {
  ReleaseCommand(super.cli);

  @override
  String get name => 'release';

  @override
  String get description => 'Discard a workspace or a materialization.';

  @override
  Future<void> run() async {
    final path = cli.locate(positional('path'));
    // The one resolution that runs the other way round: a directory is all the
    // caller has, so the repository is asked of the worktree itself. Nothing
    // standing there is the ordinary answer for a second release, and
    // deregistering is the half that matters — a directory deleted behind
    // Git's back leaves the entry standing.
    final repository = ambientGit.worktreeRepository(path);
    if (repository == null) return;
    ambientGit.worktreeRemove(repository, path: path);
  }
}
