import 'dart:io';

import 'git.dart';

export 'resolve.dart' show TxResolveError;

/// Scope operations: `tx scope new/ls/rm`.
///
/// A scope is a bare git store at `<place>/.tx/<entity>/<scope>/.git/`
/// (core.bare=true). Every thread — `main` included — is an equal linked
/// worktree at `<place>/.tx/<entity>/<scope>/<thread>/`. No thread is
/// privileged; the worktree you stand in IS the thread you act on.
final class TxScope {
  TxScope(this.entity, this.entityDir);

  final String entity;

  /// `<place>/.tx/<entity>/`
  final Directory entityDir;

  /// `tx scope new <name>` — bare store + first `main` worktree.
  ///
  /// Creates the bare git store at `<scope>/.git/` (core.bare=true) using
  /// plumbing commands so no work tree is needed for the initial commit,
  /// then adds `main` as the first equal linked worktree.
  Future<void> newScope(String name) async {
    final scopeDir = Directory('${entityDir.path}/$name');
    if (scopeDir.existsSync()) {
      throw TxGitError('scope "$name" already exists for "$entity".');
    }
    scopeDir.createSync(recursive: true);

    final gitDir = Directory('${scopeDir.path}/.git');

    // Bare store.
    await _bare(scopeDir, ['init', '--bare', '-q', '.git']);
    await _bare(scopeDir, ['config', 'user.name', entity]);
    await _bare(scopeDir, ['config', 'user.email', '$entity@bentos']);

    // Create an initial commit via plumbing — a bare repo has no work tree so
    // `git commit` doesn't work; we build the empty-tree commit manually.
    final emptyTree = (await _bareOut(
      gitDir,
      ['hash-object', '-t', 'tree', '--stdin'],
      stdinData: '',
    ))
        .trim();
    final authorEnv = {
      'GIT_AUTHOR_NAME': entity,
      'GIT_AUTHOR_EMAIL': '$entity@bentos',
      'GIT_COMMITTER_NAME': entity,
      'GIT_COMMITTER_EMAIL': '$entity@bentos',
    };
    final commitSha = (await _bareOut(
      gitDir,
      ['commit-tree', emptyTree, '-m', 'tx scope new $name'],
      extraEnv: authorEnv,
    ))
        .trim();
    await _bareRun(gitDir, ['update-ref', 'refs/heads/main', commitSha]);
    await _bareRun(gitDir, ['symbolic-ref', 'HEAD', 'refs/heads/main']);

    // Add main as the first (equal) linked worktree.
    final mainDir = '${scopeDir.path}/main';
    await _bareRun(gitDir, ['worktree', 'add', mainDir, 'main']);
  }

  /// `tx scope ls` — the entity's scopes (subdirectories with a `.git/`).
  List<String> listScopes() {
    if (!entityDir.existsSync()) return [];
    return entityDir
        .listSync()
        .whereType<Directory>()
        .where((d) => Directory('${d.path}/.git').existsSync())
        .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toList()
      ..sort();
  }

  /// `tx scope rm <name>` — remove an entire existence.
  void removeScope(String name) {
    final scopeDir = Directory('${entityDir.path}/$name');
    if (!scopeDir.existsSync()) {
      throw TxGitError('scope "$name" does not exist for "$entity".');
    }
    scopeDir.deleteSync(recursive: true);
  }

  // --- helpers for bare-repo git invocations --------------------------------

  /// Run `git -C <scopeDir> --git-dir=.git <args>` (init / config).
  Future<void> _bare(Directory scopeDir, List<String> args) async {
    final result = await Process.run(
      'git',
      ['-C', scopeDir.path, '--git-dir=.git', ...args],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      final err = String.fromCharCodes(result.stderr as List<int>).trim();
      throw TxGitError('git ${args.join(' ')} failed: $err');
    }
  }

  /// Run `git --git-dir=<gitDir> <args>` with no work tree.
  Future<void> _bareRun(
    Directory gitDir,
    List<String> args, {
    Map<String, String>? extraEnv,
  }) async {
    final result = await Process.run(
      'git',
      ['--git-dir', gitDir.path, ...args],
      environment: {...Platform.environment, ...?extraEnv},
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      final err = String.fromCharCodes(result.stderr as List<int>).trim();
      throw TxGitError('git ${args.join(' ')} failed: $err');
    }
  }

  /// Like [_bareRun] but returns decoded stdout. Optionally pipes [stdinData].
  Future<String> _bareOut(
    Directory gitDir,
    List<String> args, {
    String? stdinData,
    Map<String, String>? extraEnv,
  }) async {
    final process = await Process.start(
      'git',
      ['--git-dir', gitDir.path, ...args],
      environment: {...Platform.environment, ...?extraEnv},
    );
    if (stdinData != null) {
      process.stdin.write(stdinData);
    }
    await process.stdin.close();
    final stdout = await process.stdout.transform(SystemEncoding().decoder).join();
    final stderr = await process.stderr.transform(SystemEncoding().decoder).join();
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw TxGitError('git ${args.join(' ')} failed: ${stderr.trim()}');
    }
    return stdout;
  }
}
