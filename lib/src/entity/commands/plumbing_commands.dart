import 'dart:convert';
import 'dart:io';

import '../entity.dart';
import '../entity_runner.dart';
import '../event.dart';
import '../transaction.dart';
import '../../git/git.dart';
import '../../git/git_ambient.dart';
import 'entity_command.dart';

/// The plumbing family exists for what does not fit the bracket: `resolve`,
/// `tip`, `path`, `emit` and `release` are the escape hatches and the hook's
/// own callee, kept at the shell for programs that are not a callback.
///
/// **`work` and `commit` are gone.** They were the private-area CAS's own
/// three-process shape — no closure spanning `work`, `commit` and `release` —
/// and that path is retired: `act` commits in the instance's own attached
/// worktree now, and a caller opening a private area beside it would land a
/// ref move from outside the tree that follows it, which is exactly the
/// corruption the new path exists to remove.

/// `entity resolve <coord>` → path.
///
/// The selection turned into somewhere to stand: where the instance actually
/// **is**, read from [Instance.standingAt] — the substrate's own record of
/// which materializations follow this branch, never a guess built from the
/// entity's name alone. A coordinate is a selection and never a runtime
/// address — coordinate resolves, path operates — and this is the verb that
/// crosses between the two.
///
/// Zero or one — never several, since [standingAt] can only ever answer for
/// one address or none, a fact Git enforces on the branch itself. Zero is not
/// found: a coordinate that stands nowhere has nothing to resolve to, bogus
/// or real.
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
    if (standingAt == null) {
      cli.err.writeln('entity resolve: stands nowhere: $coord');
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    cli.out.writeln(standingAt);
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
