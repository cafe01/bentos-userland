import 'dart:io';

import 'git.dart';

/// Thread operations: `tx thread new/ls/path/fork/join/rm`.
///
/// All operations address the same bare store at `<scope>/.git/`; threads
/// are equal linked worktrees at `<scope>/<thread>/`. No thread is privileged.
final class TxThread {
  TxThread(this.entity, this.scopeDir);

  final String entity;

  /// `<place>/.tx/<entity>/<scope>/`
  final Directory scopeDir;

  Directory get _gitDir => Directory('${scopeDir.path}/.git');

  /// `tx thread new <name>` — new branch + materialized worktree off HEAD.
  Future<void> newThread(String name) async {
    _requireScope();
    await _wt(['worktree', 'add', '${scopeDir.path}/$name', '-b', name]);
  }

  /// `tx thread ls` — threads + their live worktree paths.
  ///
  /// Skips the bare entry. [cwdPath] (absolute, no trailing slash) marks
  /// the currently-active thread with `*`.
  Future<void> listThreads({String? cwdPath}) async {
    _requireScope();
    for (final e in await _worktreeEntries()) {
      final isCurrent = cwdPath != null && cwdPath.startsWith(e.path);
      stdout.writeln('${isCurrent ? '*' : ' '} ${e.name.padRight(16)} ${e.path}');
    }
  }

  /// `tx thread path [<name>]` — print a thread's worktree dir.
  ///
  /// [name] names the thread explicitly. If omitted, [cwdThread] (from CWD
  /// inference) is used; falls back to `main`.
  Future<void> printPath({String? name, String? cwdThread}) async {
    _requireScope();
    final target = name ?? cwdThread ?? 'main';
    final entries = await _worktreeEntries();
    final entry = entries.where((e) => e.name == target).firstOrNull;
    if (entry == null) {
      throw TxGitError('thread "$target" not found in scope "${scopeDir.path}".');
    }
    stdout.writeln(entry.path);
  }

  /// `tx thread fork <new> [src]` — branch `new` from `src` (default: main).
  Future<void> fork(String newName, {String src = 'main'}) async {
    _requireScope();
    await _wt(['worktree', 'add', '${scopeDir.path}/$newName', '-b', newName, src]);
  }

  /// `tx thread join <src> [<dst>]` — fold src into dst (default: main).
  ///
  /// Runs `git merge` inside the dst worktree directory. The verb is `join`:
  /// a thread is joined back — git merge is only the mechanism.
  Future<void> join(String src, {String dst = 'main'}) async {
    _requireScope();
    final dstDir = Directory('${scopeDir.path}/$dst');
    if (!dstDir.existsSync()) {
      throw TxGitError('thread "$dst" does not exist in scope.');
    }
    await git(dstDir, ['merge', src, '--no-edit']);
  }

  /// `tx thread rm <name>` — tear down a thread's worktree (history stays).
  Future<void> removeThread(String name) async {
    _requireScope();
    await _wt(['worktree', 'remove', '${scopeDir.path}/$name']);
  }

  // --- internals ------------------------------------------------------------

  void _requireScope() {
    if (!_gitDir.existsSync()) {
      throw TxGitError(
        'scope at "${scopeDir.path}" does not exist. '
        'Run `tx scope new <name>` first.',
      );
    }
  }

  /// Run a git command addressed to the bare store via `--git-dir`.
  Future<void> _wt(List<String> args) async {
    final result = await Process.run(
      'git',
      ['--git-dir', _gitDir.path, ...args],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      final err = String.fromCharCodes(result.stderr as List<int>).trim();
      throw TxGitError('git ${args.join(' ')} failed: $err');
    }
  }

  /// `git --git-dir <gitDir> <args>` returning stdout.
  Future<String> _wtOut(List<String> args) async {
    final result = await Process.run(
      'git',
      ['--git-dir', _gitDir.path, ...args],
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw TxGitError('git ${args.join(' ')} failed: $err');
    }
    return result.stdout as String;
  }

  /// Parse `git worktree list`, skipping the bare entry.
  Future<List<({String name, String path})>> _worktreeEntries() async {
    final out = await _wtOut(['worktree', 'list']);
    final entries = <({String name, String path})>[];
    for (final line in out.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.contains('(bare)')) continue;
      // Format: "/abs/path  abc1234 [branch]"
      final spaceIdx = trimmed.indexOf(' ');
      final worktreePath = spaceIdx == -1 ? trimmed : trimmed.substring(0, spaceIdx);
      final name = worktreePath.split('/').last;
      entries.add((name: name, path: worktreePath));
    }
    return entries;
  }
}
