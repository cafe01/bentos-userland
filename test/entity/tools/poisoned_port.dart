import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/git/process_git.dart';

/// A child process that drives the port under a **poisoned environment** —
/// `GIT_DIR` and its family exported by whoever spawned it, all of them lies.
///
/// It exists because `Platform.environment` is fixed for the life of a Dart
/// process: a test cannot poison its own environment and then watch the port
/// clean it. Only a child can be born dirty, and this is that child.
///
/// Usage: `poisoned_port <gitDir> <ref>` — lands one act on that ref and prints
/// the sha it landed. What the caller then asserts is where the bytes went.
void main(List<String> args) {
  const git = ProcessGit();
  final gitDir = args[0];
  final ref = args[1];

  final tip = git.revParse(gitDir, ref);
  if (tip == null) {
    stderr.writeln('no such ref: $ref');
    exit(1);
  }

  final work = Directory.systemTemp.createTempSync('poisoned-work-');
  try {
    File('${work.path}/note').writeAsStringSync('written under a lie\n');
    final tree = git.writeTree(gitDir, workTree: work.path);
    final sha = git.commitTree(
      gitDir,
      tree: tree,
      parents: [tip.sha],
      message: Action.messageFor('note'),
      actor: const Actor('poisoned'),
    );
    if (!git.updateRef(gitDir, ref: ref, newCommit: Commit(sha), expected: tip)) {
      stderr.writeln('the swap was refused');
      exit(1);
    }
    stdout.writeln(sha);
  } finally {
    work.deleteSync(recursive: true);
  }
}
