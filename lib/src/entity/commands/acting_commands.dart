import 'dart:io';

import '../../git/model/actor.dart';
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
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('act: <coord> <action> are required');
    final written = body();
    if (written.isEmpty) {
      usageException('act: the body is required — `-- <command>`');
    }

    final actor = argResults!['actor'] as String?;
    final result = await cli.instanceAt(coordinate(), place: placeOption).act(
      rest[1],
      (workspace) async {
        // The body writes in the private area and nowhere else: it is handed
        // the directory as its own, which is what keeps two acting bodies from
        // corrupting each other one floor below the swap.
        final ran = await Process.start(
          written.first,
          written.skip(1).toList(),
          workingDirectory: workspace.directory.path,
        );
        // Both of the body's streams are the operator's to read, and neither
        // is ours to publish: stdout here belongs to the landed sha, so that
        // `sha=$(entity act … -- …)` composes however loudly the body talks.
        final said = [
          ran.stdout.forEach(cli.writeThrough),
          ran.stderr.forEach(cli.writeThrough),
        ];
        final code = await ran.exitCode;
        await Future.wait(said);
        if (code != 0) throw _BodyFailed(code);
      },
      actor: actor == null ? null : Actor(actor),
    );
    cli.report(result);
  }
}

/// The body exited non-zero, so there is nothing worth landing. Private: it
/// never leaves this file — the bracket unwinds on it, releases the area, and
/// the coreutil answers with the body's own number.
final class _BodyFailed implements Exception {
  const _BodyFailed(this.code);
  final int code;
}

/// `entity read <coord>:<path> [--at <sha>]` — bytes, without materializing.
///
/// The reading a federated site that only reacts lives on: it holds no worktree
/// at all, and still reads the state it must judge — at the tip by default, and
/// at any point of the instance's line when the judgment is about one.
final class ReadCommand extends EntityCommand {
  ReadCommand(super.cli) {
    argParser.addOption(
      'at',
      help: 'Read at this commit rather than at the tip.',
      valueHelp: 'sha',
    );
  }

  @override
  String get name => 'read';

  @override
  String get description => 'Read content at a ref, with no worktree.';

  @override
  Future<void> run() async {
    final coord = coordinate();
    final path = coord.path;
    if (path == null) {
      usageException('read: expected <entity>:<instance>:<path>');
    }
    // Bytes, verbatim: an instance may hold anything, and a coreutil that
    // decoded on the way out would be lying about what is stored.
    cli.writeBytes(
      cli.instanceAt(coord, place: placeOption).read(path, at: pointInHistory()),
    );
  }
}

/// `entity materialize <coord> [--at <path>]` — the persistent worktree, for a
/// face.
///
/// It belongs to whoever looks, necessarily lags, and must be refreshed before
/// anything writes through it. An acting body never uses one: it takes a
/// private area of its own, which is what keeps a race honest.
final class MaterializeCommand extends EntityCommand {
  MaterializeCommand(super.cli) {
    argParser.addOption('at', help: 'Where the worktree stands.', valueHelp: 'path');
  }

  @override
  String get name => 'materialize';

  @override
  String get description => 'Stand a persistent worktree beside an instance.';

  @override
  Future<void> run() async {
    final at = argResults!['at'] as String?;
    final standing = cli
        .instanceAt(coordinate(), place: placeOption)
        .materialize(at: at == null ? null : cli.locate(at));
    cli.out.writeln(standing.directory.path);
  }
}

/// The number a failed body leaves behind — the caller's own program, reported
/// verbatim, because the coreutil has no better word for what it means.
int? bodyFailureCode(Object error) =>
    error is _BodyFailed ? error.code : null;
