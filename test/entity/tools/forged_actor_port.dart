import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';

/// A child process born under a **poisoned identity** — `GIT_AUTHOR_NAME` and
/// `GIT_AUTHOR_EMAIL` exported by whoever spawned it, naming somebody else.
///
/// `Platform.environment` is fixed for the life of a Dart process, so the only
/// honest proof that `entity commit` signs its stated actor rather than the
/// ambient one is a child actually born dirty — the same reasoning
/// `poisoned_port.dart` stands on, aimed at identity instead of location.
///
/// Usage: `forged_actor_port <root> <coord> <action> <worktree> <parent>
/// <actor> [actorEmail]` — runs `entity commit` in process with the given
/// `--actor` (and `--actor-email` where given) and prints the landed sha.
void main(List<String> args) async {
  const git = ProcessGit();
  final root = args[0];
  final coord = args[1];
  final action = args[2];
  final worktree = args[3];
  final parent = args[4];
  final actor = args[5];
  final actorEmail = args.length > 6 ? args[6] : null;

  final out = StringBuffer();
  final err = StringBuffer();
  final runner = EntityRunner(out: out, err: err, currentDirectory: root);
  await runWithGitAsync(
    git,
    () => runner.run([
      'commit', coord, action,
      '-w', worktree, '--parent', parent, '--actor', actor,
      if (actorEmail != null) '--actor-email',
      if (actorEmail != null) actorEmail,
    ]),
  );
  if (runner.exitCode != 0) {
    stderr.write(err.toString());
    exit(runner.exitCode);
  }
  stdout.write(out.toString());
}
