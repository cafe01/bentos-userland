import 'dart:convert';
import 'dart:io';

import '../entity.dart';
import '../entity_runner.dart';
import '../event.dart';
import '../transaction.dart';
import '../../git/git.dart';
import '../../git/git_ambient.dart';
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
/// The selection turned into somewhere to stand: where the instance actually
/// **is**, read from [Instance.standingAt] — the substrate's own record of
/// which materializations follow this branch, never a guess built from the
/// entity's name alone. A coordinate is a selection and never a runtime
/// address — coordinate resolves, path operates — and this is the verb that
/// crosses between the two.
///
/// Zero, one, or several equally legal answers. Zero is not found: a
/// coordinate that stands nowhere has nothing to resolve to, bogus or real.
/// Several is answered by the first, sorted — deterministic, and the same
/// tie-break [standingAt] already sorts for.
final class ResolveCommand extends EntityCommand {
  ResolveCommand(super.cli);

  @override
  String get name => 'resolve';

  @override
  String get description => 'Resolve a coordinate to a path.';

  @override
  List<String> get positionalLabels => const ['coord'];

  @override
  Future<void> run() async {
    final coord = coordinate();
    final standingAt = cli.instanceAt(coord, place: placeOption).standingAt;
    if (standingAt.isEmpty) {
      cli.err.writeln('entity resolve: stands nowhere: $coord');
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    cli.out.writeln(standingAt.first);
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
  List<String> get positionalLabels => const ['coord'];

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
  List<String> get positionalLabels => const ['name'];

  @override
  Future<void> run() async {
    final named = requirePositionals().first;
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
  List<String> get positionalLabels => const ['coord'];

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
    takesActor();
    argParser
      ..addOption('worktree', abbr: 'w', help: 'The area opened by `work`.')
      ..addOption('parent', help: 'The value the ref must still hold.')
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
  List<String> get positionalLabels => const ['coord', 'action'];

  @override
  Future<void> run() async {
    final rest = requirePositionals();
    final area = argResults!['worktree'] as String?;
    if (area == null) usageException('commit: -w <path> is required');
    final parent = argResults!['parent'] as String?;
    if (parent == null) usageException('commit: --parent <sha> is required');

    final coord = coordinate();
    final instance = cli.instanceAt(coord, place: placeOption);
    final actor = statedActor();
    final workspace = Workspace(
      directory: Directory(cli.locate(area)),
      gitDir: gitDirOf(instance.entity),
      ref: instance.ref,
      expectedTip: Commit(parent),
    );
    cli.report(
      workspace.commit(
        rest[1],
        actor: actor,
        say: argResults!['say'] as String?,
      ),
    );
  }
}

/// `entity emit <name> <phase>` — the trampoline's only callee, and the whole
/// content of "the hook publishes." Reads Git's own `<old> <new> <ref>`
/// triples off stdin, one per line, and hands them to [Entity.emit] under the
/// ontology's own phase.
///
/// **The phase mapping is this verb's job, not the shim's.** The shim forwards
/// Git's own word — `prepared`, `committed`, `aborted` — verbatim; translating
/// it into [EventPhase] happens here, once, so the shim stays six lines with no
/// vocabulary of its own that could drift from this one.
///
/// Nobody but a hook has honest reason to call this by hand: reaching for it
/// means publishing an event that did not happen. It stands in plumbing for the
/// same reason `path` does — the surface makes that visible rather than
/// impossible.
final class EmitCommand extends EntityCommand {
  EmitCommand(super.cli);

  @override
  String get name => 'emit';

  @override
  String get description =>
      "Publish a ref transaction into the primitive — the hook's own verb.";

  @override
  List<String> get positionalLabels => const ['name', 'phase'];

  @override
  Future<void> run() async {
    final rest = requirePositionals();
    final entity = cli.entityNamed(rest[0], place: placeOption);
    final phase = _phaseOf(rest[1]);

    final updates = <TransactionRefUpdate>[];
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      try {
        updates.add(TransactionRefUpdate.parse(line));
      } on FormatException catch (e) {
        usageException('emit: ${e.message}: "$line"');
      }
    }

    cli.exitCode = await entity.emit(phase, updates);
  }

  /// Git's own word for the phase, mapped to the ontology's. The shim never
  /// emits a fourth word, and neither should anyone typing this by hand.
  EventPhase _phaseOf(String word) => switch (word) {
        'prepared' => EventPhase.attempted,
        'committed' => EventPhase.landed,
        'aborted' => EventPhase.refused,
        _ => usageException(
            'emit: "$word" is not a transaction phase — '
            'prepared, committed or aborted',
          ),
      };
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
  List<String> get positionalLabels => const ['path'];

  @override
  Future<void> run() async {
    final path = cli.locate(requirePositionals().first);
    // The one resolution that runs the other way round: a directory is all the
    // caller has, so the repository is asked of the worktree itself. Nothing
    // standing there is the ordinary answer for a second release, and
    // deregistering is the half that matters — a directory deleted behind
    // Git's back leaves the entry standing.
    final repository = ambientGit.worktreeRepository(path);
    if (repository == null) {
      // **Absent and foreign are not one answer.** An empty path is a second
      // release and costs nothing; a directory that exists and is not ours is a
      // caller aiming at somebody else's disk, and answering that with a silent
      // zero is how a mistyped path became a deletion nobody was told about.
      if (Directory(path).existsSync()) throw WorktreeNotOurs(path);
      return;
    }
    ambientGit.worktreeRemove(repository, path: path);
  }
}
