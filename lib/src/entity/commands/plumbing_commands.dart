import 'entity_command.dart';

/// The plumbing family exists for what does not fit the bracket, and **it is
/// the family that matters most: the callers here are programs.**
///
/// `work` and `commit` are also the one shape a callback cannot serve — three
/// separate processes, no closure spanning them — which is why the pieces
/// survive at the shell after the library made the bracket its only safe path.

/// `entity resolve <coord>` → path.
final class ResolveCommand extends EntityCommand {
  ResolveCommand(super.cli);

  @override
  String get name => 'resolve';

  @override
  String get description => 'Resolve a coordinate to a path.';

  @override
  Future<void> run() => throw UnimplementedError('entity resolve');
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
  Future<void> run() => throw UnimplementedError('entity tip');
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
  Future<void> run() => throw UnimplementedError('entity path');
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
  Future<void> run() => throw UnimplementedError('entity work');
}

/// `entity commit -w <path> <action> --parent <sha> [--actor <a>]` — close an
/// act opened by `work`.
///
/// `--parent` is the whole reason the last step is plumbing: ordinary Git
/// commits onto whatever tip it finds when it runs, and an act must instead
/// name the value the ref is required to still hold.
final class CommitCommand extends EntityCommand {
  CommitCommand(super.cli) {
    argParser
      ..addOption('worktree', abbr: 'w', help: 'The area opened by `work`.')
      ..addOption('parent', help: 'The value the ref must still hold.')
      ..addOption('actor', help: 'The identity written as the author.');
  }

  @override
  String get name => 'commit';

  @override
  String get description => 'Land an act from a private area, by compare-and-swap.';

  @override
  Future<void> run() => throw UnimplementedError('entity commit');
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
  Future<void> run() => throw UnimplementedError('entity release');
}
