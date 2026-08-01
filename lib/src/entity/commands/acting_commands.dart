import 'entity_command.dart';

/// `entity act <coord> <action> [--actor <a>] -- <command>` — the porcelain of
/// the whole write: the bracket with the command as its body, so an actor
/// script is its own body and nothing else.
///
/// It opens a private area at the tip, runs the command in it, commits under
/// the declared noun with compare-and-swap, and releases. **It does not invoke
/// the entity** — nothing executes an object whose state changes by being
/// written to. The command is the caller's own write.
///
/// Exits 3 when the act was refused: the ref moved, or a listener at
/// `.attempted` said no. Both are ordinary, and a caller retries by re-reading.
final class ActCommand extends EntityCommand {
  ActCommand(super.cli) {
    argParser.addOption('actor', help: 'The identity written as the author.');
  }

  @override
  String get name => 'act';

  @override
  String get description => 'Take an action: write in a private area and land it.';

  @override
  Future<void> run() => throw UnimplementedError('entity act');
}

/// `entity read <coord>:<path>` — bytes, without materializing.
///
/// The reading a federated site that only reacts lives on: it holds no worktree
/// at all, and still reads the state it must judge.
final class ReadCommand extends EntityCommand {
  ReadCommand(super.cli);

  @override
  String get name => 'read';

  @override
  String get description => 'Read content at a ref, with no worktree.';

  @override
  Future<void> run() => throw UnimplementedError('entity read');
}

/// `entity materialize <coord> [--at <path>]` — the persistent worktree, for a
/// face.
///
/// It belongs to whoever looks, necessarily lags the instance, and must be
/// refreshed before anything writes through it. An acting body never uses one:
/// it takes a private area of its own, which is what keeps a race honest.
final class MaterializeCommand extends EntityCommand {
  MaterializeCommand(super.cli) {
    argParser.addOption('at', help: 'Where the worktree stands.', valueHelp: 'path');
  }

  @override
  String get name => 'materialize';

  @override
  String get description => 'Stand a persistent worktree beside an instance.';

  @override
  Future<void> run() => throw UnimplementedError('entity materialize');
}
