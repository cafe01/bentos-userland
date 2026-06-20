import 'dart:io';

import 'git.dart';

/// Day-to-day verbs: `tx commit / log / rewind`.
///
/// All three act on the worktree you stand in — CWD is the thread.
/// No scope or entity awareness needed; git operates on whatever repo
/// owns the CWD.
final class TxDay {
  TxDay(this.worktree);

  /// The worktree directory to act on — the CWD the caller stood in.
  final Directory worktree;

  /// `tx commit [-m msg]` — stage everything and commit.
  ///
  /// [message] defaults to `"tx commit"` when omitted; the app is expected
  /// to supply meaningful messages for meaningful mutations.
  Future<void> commit({String message = 'tx commit'}) async {
    await git(worktree, ['add', '-A']);
    await git(worktree, ['commit', '--allow-empty', '-m', message]);
  }

  /// `tx log` — this thread's commit trace, one line per commit.
  Future<void> log() async {
    final out = await gitOut(worktree, ['log', '--oneline']);
    stdout.write(out);
  }

  /// `tx rewind <n>` — reset the worktree back [n] commits.
  ///
  /// [n] counts commits, not turns. Git errors if n exceeds history depth.
  Future<void> rewind(int n) async {
    if (n < 1) throw TxGitError('rewind: n must be >= 1, got $n.');
    await git(worktree, ['reset', '--hard', 'HEAD~$n']);
  }
}
