import 'dart:io';

import '../../git/model/actor.dart';
import '../entity_runner.dart';
import 'entity_command.dart';

/// `entity act <coord> <action> [--actor <a>] [--say <phrase>] -- <command>` —
/// the porcelain of the whole write: the bracket with the command as its body,
/// so an actor script is its own body and nothing else.
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
    argParser
      ..addOption('actor', help: 'The identity written as the author.')
      ..addOption(
        'actor-email',
        help: 'The address written beside --actor. Requires --actor. Absent, '
            'a placeholder is derived — harmless, since nothing reads meaning '
            'into the address — but a caller that means to state a real one '
            'and cannot could only omit --actor entirely, leaving the ambient '
            'environment to sign instead.',
      )
      ..addOption(
        'say',
        help: 'The legible sentence, stored and never interpreted.',
        valueHelp: 'phrase',
      );
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
    final actorEmail = argResults!['actor-email'] as String?;
    if (actorEmail != null && actor == null) {
      usageException('act: --actor-email requires --actor');
    }
    final result = await cli.instanceAt(coordinate(), place: placeOption).act(
      rest[1],
      (workspace) async {
        // The body writes in the private area and nowhere else: it is handed
        // the directory as its own, which is what keeps two acting bodies from
        // corrupting each other one floor below the swap.
        final Process ran;
        try {
          ran = await Process.start(
            written.first,
            written.skip(1).toList(),
            workingDirectory: workspace.directory.path,
          );
        } on ProcessException catch (e) {
          // The body could not be started at all — almost always a relative
          // path, which resolves against the private area and not against the
          // directory the caller typed it in. That is the act's isolation
          // working as designed, and the only thing wrong is that the caller
          // was never told where their command was looked for. Told plainly it
          // is one edit; left as a raw ProcessException it is a stack trace
          // about a Dart library the reader did not open.
          throw BodyNotStartable(written.first, workspace.directory.path, e);
        }
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
      actor: actor == null ? null : Actor(actor, email: actorEmail),
      say: argResults!['say'] as String?,
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

/// The body could not be started: nothing ran, nothing landed.
///
/// Public because the runner reports it, and its message is the surface that
/// teaches where an act's body runs — a place no `--help` mentions and every
/// caller with a relative path discovers the hard way.
final class BodyNotStartable implements Exception {
  const BodyNotStartable(this.command, this.directory, this.cause);

  /// The executable as the caller wrote it.
  final String command;

  /// The act's private area — where it was looked for.
  final String directory;

  final ProcessException cause;

  /// True when the caller wrote a path that only means something relative to
  /// where they stood, which is the case worth explaining.
  bool get isRelative => command.contains('/') && !command.startsWith('/');

  @override
  String toString() => [
        'entity: cannot run "$command": ${cause.message}',
        "the act's body runs in the act's own private area ($directory), "
            'never in the directory you typed the command in',
        if (isRelative)
          'a relative path is resolved there — give an absolute path'
        else
          'give an absolute path, or a name found on PATH',
      ].join('\n  ');
}

/// `entity read <coord>:<path> [--as-of <sha>]` — bytes, without materializing.
///
/// The reading a federated site that only reacts lives on: it holds no worktree
/// at all, and still reads the state it must judge — at the tip by default, and
/// at any point of the instance's line when the judgment is about one.
final class ReadCommand extends EntityCommand {
  ReadCommand(super.cli) {
    takesPointInHistory();
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

/// `entity refresh <coord> <path>` — bring a standing worktree up to the
/// instance's present tip.
///
/// A face lags by construction: another participant may land an act at any
/// moment, and nothing refreshes anyone's tree for them. This is the looker's
/// own verb, and the sibling of `release` — both act on a directory somebody
/// else's process stood up.
///
/// **It takes the coordinate as well as the path**, for the reason `commit`
/// does: a worktree of ours is checked out detached, so the directory can
/// report the repository it belongs to and the commit it stands at, but never
/// the ref it follows — and the ref is the whole question, since refreshing
/// means catching up with where that ref now points.
///
/// A tree already standing at the tip is left alone, and so is one that follows
/// no ref at all: a place's materialization stands at a commit declared from
/// outside, and moving it is the declarer's act.
///
/// **Absence is stood up, not refused.** *Make this directory be the ref* is
/// one act to whoever needs the files, and a verb that answered *nothing here*
/// would be the only verb in reach of someone whose tree went missing — which
/// is precisely the reader a refusal elsewhere sends here. A directory holding
/// content this repository never registered is the one case that refuses: it is
/// named and left exactly as it stands.
final class RefreshCommand extends EntityCommand {
  RefreshCommand(super.cli);

  @override
  String get name => 'refresh';

  @override
  String get description => 'Bring a standing worktree up to the tip.';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('refresh: <coord> <path> are required');
    final path = cli.locate(rest[1]);
    final standing = cli.instanceAt(coordinate(), place: placeOption);
    final face = standing.materialization(path);
    final outcome = face.refresh();
    if (!outcome.moved) {
      // A decided refusal, not a stumble: the tree carries changes the move
      // would overwrite, and it is left exactly as it stands. Barred, like
      // every other decline this coreutil reports as itself rather than as a
      // success that happened to change nothing.
      cli.err.writeln('entity: barred — tree stands behind the line: ${outcome.report}');
      cli.exitCode = EntityRunner.barredCode;
      return;
    }
    cli.out.writeln(face.at?.sha ?? '');
  }
}

/// The number a failed body leaves behind — the caller's own program, reported
/// verbatim, because the coreutil has no better word for what it means.
int? bodyFailureCode(Object error) =>
    error is _BodyFailed ? error.code : null;
