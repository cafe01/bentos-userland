import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';

/// A child process that lands one act through the **shipped path** — a real
/// attached worktree, `commitInWorktree` — under a poisoned environment.
///
/// It exists for the same reason [poisoned_port.dart] does:
/// `Platform.environment` is fixed for the life of a Dart process, so a test
/// cannot poison its own environment and then watch the port clean it. Only a
/// child born dirty can prove the guard, and this is that child for the path
/// we actually ship — `poisoned_port.dart` still drives the retired
/// compare-and-swap path and is not extended here.
///
/// Usage: `poisoned_act <gitDir> <path> <ref> <branch>` — attaches a worktree
/// at [path] to [branch] (starting from [ref]'s tip), writes one file and
/// commits as a real, named actor. What the caller poisons is the ambient
/// identity — `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`,
/// `GIT_COMMITTER_EMAIL` — and what it then asserts is whose name and email
/// the landed commit actually carries, read back from git itself.
void main(List<String> args) {
  const git = ProcessGit();
  final gitDir = args[0];
  final path = args[1];
  final ref = args[2];
  final branch = args[3];

  final tip = git.revParse(gitDir, ref);
  if (tip == null) {
    stderr.writeln('no such ref: $ref');
    exit(1);
  }

  git.worktreeAdd(gitDir, path: path, at: tip, branch: branch);
  File('$path/note').writeAsStringSync('written by the real actor\n');
  final outcome = git.commitInWorktree(
    path,
    message: 'poisoned act',
    actor: Actor('real actor', email: 'real@test.local'),
  );
  final landed = outcome.commit;
  if (landed == null) {
    stderr.writeln('refused: ${outcome.report}');
    exit(1);
  }
  stdout.writeln(landed.sha);
}
