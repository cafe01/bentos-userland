import 'dart:io';

import '../action.dart';
import '../entity_runner.dart';
import '../instance.dart';
import 'entity_command.dart';

/// `entity act <coord> <action> [--actor <a>] [--say <phrase>] -- <command>` —
/// the porcelain of the whole write: the command is the body, so an actor
/// script is its own body and nothing else.
///
/// It runs the command **in the instance's own worktree** — stood up at the
/// convention address if none stands — and commits there, which is how the
/// branch moves. **It does not invoke the entity**: nothing executes an object
/// whose state changes by being written to. The command is the caller's own
/// write.
///
/// It refuses a tree carrying uncommitted work, and restores the tree when the
/// act does not land. Exits 3 when a listener at `.attempted` said no.
final class ActCommand extends EntityCommand {
  ActCommand(super.cli) {
    takesActor();
    takesBody();
    argParser.addOption(
        'say',
        help: 'The legible sentence, stored and never interpreted.',
        valueHelp: 'phrase',
      );
  }

  @override
  String get name => 'act';

  @override
  String get description =>
      "Take an action: write in the instance's own tree and commit there.";

  @override
  List<String> get positionalLabels => const ['coord', 'action'];

  @override
  Future<void> run() async {
    final rest = requirePositionals();
    final written = body();
    if (written.isEmpty) {
      usageException('act: the body is required — `-- <command>`');
    }

    // Before anything stands up: an act nobody signed is not sayable, and
    // refusing after a worktree exists would make the refusal cost something.
    final actor = statedActor();
    final result = await _reporting(() => cli.instanceAt(coordinate(), place: placeOption).act(
      rest[1],
      (area) async {
        // The body writes in the instance's own tree, and its whole content is
        // the payload: the act refused to start against a tree carrying
        // anything else, so what stands here afterwards is this act's alone.
        final Process ran;
        try {
          ran = await Process.start(
            written.first,
            written.skip(1).toList(),
            workingDirectory: area.directory.path,
          );
        } on ProcessException catch (e) {
          // The body could not be started at all — almost always a relative
          // path, which resolves against the instance's tree and not against
          // the directory the caller typed it in. That is where the act
          // happens by law, and the only thing wrong is that the caller was
          // never told where their command was looked for. Told plainly it is
          // one edit; left as a raw ProcessException it is a stack trace about
          // a Dart library the reader did not open.
          throw BodyNotStartable(written.first, area.directory.path, e);
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
      actor: actor,
      say: argResults!['say'] as String?,
    ));
    if (result case Barred(:final discarded) when discarded.isNotEmpty) {
      // Nothing landed, so the tree went back to where it stood — and what
      // that cost is said out loud. A silent deletion of somebody's output is
      // how a tool earns distrust it never recovers from.
      cli.err.writeln('entity: the act did not land, so its tree was restored '
          'and these were discarded:');
      for (final path in discarded) {
        cli.err.writeln('  $path');
      }
    }
    cli.report(result);
  }

  /// Runs the act, and turns an [ActUnwound] back into the body's own failure
  /// after saying what the restore destroyed.
  ///
  /// The cause is what the caller must see — their command's exit code, or the
  /// unstartable path — and the discarded list is the part only the act can
  /// report. Rethrowing the cause keeps every number this coreutil answers
  /// with exactly as it was.
  Future<ActionResult> _reporting(Future<ActionResult> Function() acting) async {
    try {
      return await acting();
    } on ActUnwound catch (unwound) {
      if (unwound.discarded.isNotEmpty) {
        cli.err.writeln('entity: the act did not land, so its tree was '
            'restored and these were discarded:');
        for (final path in unwound.discarded) {
          cli.err.writeln('  $path');
        }
      }
      throw unwound.cause;
    }
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

  /// The instance's own tree — where the body ran, and where it was looked
  /// for.
  final String directory;

  final ProcessException cause;

  /// True when the caller wrote a path that only means something relative to
  /// where they stood, which is the case worth explaining.
  bool get isRelative => command.contains('/') && !command.startsWith('/');

  @override
  String toString() => [
        'entity: cannot run "$command": ${cause.message}',
        "the act's body runs in the instance's own tree ($directory), "
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
  List<String> get positionalLabels => const ['coord:path'];

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
/// **The same tree an act commits in**, attached to the instance's branch and
/// standing at the convention address unless `--at` names another. Idempotent:
/// a tree already standing there is left alone, because someone may be looking
/// at it.
final class MaterializeCommand extends EntityCommand {
  MaterializeCommand(super.cli) {
    argParser.addOption('at', help: 'Where the worktree stands.', valueHelp: 'path');
  }

  @override
  String get name => 'materialize';

  @override
  String get description => 'Stand a persistent worktree beside an instance.';

  @override
  List<String> get positionalLabels => const ['coord'];

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
/// The verb of a **face**: a detached tree at a commit, which lags by
/// construction because nothing moves it when the instance acts. The
/// instance's own attached tree does not come through here — a commit taken in
/// it moves the branch by happening — and this says so rather than passing in
/// silence.
///
/// The sibling of `release`: both act on a directory somebody else's process
/// stood up.
///
/// **It takes the coordinate as well as the path**, for the reason `commit`
/// does: a face is checked out detached, so the directory can report the
/// repository it belongs to and the commit it stands at, but never the ref it
/// follows — and the ref is the whole question, since refreshing means
/// catching up with where that ref now points.
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
  List<String> get positionalLabels => const ['coord', 'path'];

  @override
  Future<void> run() async {
    final rest = requirePositionals();
    final path = cli.locate(rest[1]);
    final standing = cli.instanceAt(coordinate(), place: placeOption);
    final face = standing.materialization(path);
    final outcome = face.refresh();
    if (outcome.moved && outcome.report.isNotEmpty) {
      // Moved nothing and said so. A verb that passes in silence tells the
      // caller their reason for typing it was handled, and the one reason a
      // person refreshes an attached tree — a fetch left it behind — is the
      // one this cannot handle.
      cli.err.writeln('entity: ${outcome.report}');
    }
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
