import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;

/// Who acts, where a fixture's subject is something other than who acted.
///
/// **Stated, like every other caller's**, and spelled once so that the suite
/// says the same thing everywhere it is not the point. A test about identity
/// states its own actors instead of reaching for this one — the difference
/// between a fixture that supplies an identity and a gate that asks where a
/// real one comes from is exactly what let the defect stay green.
final Actor testActor = Actor('tester', email: 'tester@test.local');

/// The repository an installation of [name] at [placePath] stands in — the
/// documented layout, spelled once here.
///
/// A test needs it for exactly one thing: naming a **source** to install from,
/// which is a URL and not a handle. Everything else goes through the API,
/// because a caller holding a repository is the footgun the API closes.
String repositoryOf(String placePath, String name) => p.join(
      placePath,
      '.place',
      Entity.plotNamespace,
      name,
      Entity.repositoryDirName,
    );

/// Installs a real `reference-transaction` hook at [gitDir] that refuses
/// **the next** ref transaction only, with [message] on stderr, then stands
/// aside — the substrate's own gate mechanism, real, not modelled. A single
/// shot, because the refused act's own cleanup is a further ref transaction
/// (`worktreeDiscard`'s `reset --hard`) that must not itself be caught by the
/// same trap. Mirrors `process_git_test.dart`'s own fixture for the hook.
void installRefusingHook(String gitDir, String message) {
  final hooks = Directory(p.join(gitDir, 'hooks'))..createSync(recursive: true);
  final marker = p.join(hooks.path, '.refuse-next');
  File(marker).createSync();
  final hook = File(p.join(hooks.path, 'reference-transaction'));
  hook.writeAsStringSync('#!/bin/sh\n'
      '[ "\$1" = prepared ] || exit 0\n'
      '[ -e "$marker" ] || exit 0\n'
      'rm -f "$marker"\n'
      'echo "$message" >&2\n'
      'exit 1\n');
  Process.runSync('chmod', ['+x', hook.path]);
}

/// Blocks the exact index path a gitlink named [name] would stage at, the way
/// the real substrate genuinely refuses it: a tracked file already standing
/// under that path makes the index hold one entry as both a directory and a
/// blob, and `git update-index --add --cacheinfo` refuses with exactly the
/// words `'$name' appears as both a file and as a directory` — measured
/// against real Git, not modelled.
void blockGitlinkPath(Site site, String name) {
  final dir = Directory(p.join(site.root.path, name))
    ..createSync(recursive: true);
  File(p.join(dir.path, '.keep')).writeAsStringSync('blocking');
  final result = Process.runSync(
    'git',
    ['-C', site.root.path, 'add', p.join(name, '.keep')],
  );
  if (result.exitCode != 0) {
    throw ProcessException('git', ['add', name], '${result.stderr}');
  }
}

/// Undoes [blockGitlinkPath] — clears the tracked collision so the next
/// attempt at [name] is a first attempt again.
void unblockGitlinkPath(Site site, String name) {
  Process.runSync(
    'git',
    ['-C', site.root.path, 'rm', '-r', '--cached', '--ignore-unmatch', name],
  );
  final dir = Directory(p.join(site.root.path, name));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

/// A repository this system never authored — no `genesis` branch, no identity
/// trailer, one ordinary commit on `main` with an `entity.yaml` at its root
/// declaring [declaredName]. The disjoint fixture the install portal needs:
/// every other repository in this suite passes through [Entity.create], and a
/// gate that only ever meets its own hand cannot tell a real one from a copy
/// of itself.
///
/// [declaredName] is deliberately free to differ from [dirName] — the one
/// shape that actually exercises the manifest's precedence over the source's
/// own basename, rather than the two coinciding by naming accident.
///
/// Returns the bare `gitDir`, installable as a `source` — a local path is a
/// URL Git accepts natively, so no network is needed to prove this.
String foreignRepository(
  Git git,
  String rootPath, {
  required String dirName,
  required String declaredName,
}) {
  final gitDir = p.join(rootPath, dirName);
  git.init(gitDir, bare: true);
  final work = Directory.systemTemp.createTempSync('entity_foreign-');
  try {
    File(p.join(work.path, 'entity.yaml'))
        .writeAsStringSync('name: $declaredName\ntype: bentos.mem\n');
    final tree = git.writeTree(gitDir, workTree: work.path);
    final sha = git.commitTree(
      gitDir,
      tree: tree,
      parents: const [],
      message: 'initial\n',
    actor: testActor,
    );
    git.updateRef(gitDir, ref: 'refs/heads/main', newCommit: Commit(sha), expected: null);
    git.updateRef(gitDir, ref: 'HEAD', newCommit: Commit(sha), expected: null);
  } finally {
    work.deleteSync(recursive: true);
  }
  return gitDir;
}

/// A hermetic site: a real directory marked as a place, standing in a real
/// Git repository of its own — the substrate is never faked.
///
/// Real directories, because worktrees are real files by definition and the
/// port's own verbs write them. [git] defaults to the ambient production
/// port, [ProcessGit]; passed explicitly, it lets a caller stand a spy in
/// front of the real substrate (a decorator that records and delegates)
/// without inventing a second implementation of Git's own semantics.
final class Site {
  /// [initGit] is false only for the one legitimate case of a place standing
  /// outside any repository at all — see [Site.loose].
  Site([String label = 'site', Git? git, bool initGit = true])
      : git = git ?? const ProcessGit() {
    // Resolved: a place answers with its canonical root, and the system temp is
    // reached through a link on some machines. A site that kept the link's
    // spelling would have its assertions comparing two vocabularies of one path.
    root = Directory(Directory.systemTemp
        .createTempSync('entity_$label')
        .resolveSymbolicLinksSync());
    Directory('${root.path}/.place').createSync(recursive: true);
    File('${root.path}/.place/place.yaml').writeAsStringSync('name: $label\n');
    // The site lies inside a repository, because a place does: the pin is a
    // gitlink in the superproject's index, so `Place._writePin` asks the port
    // which working tree answers for this directory and returns early when the
    // answer is none. A site that never declared itself left the fixture with
    // no pin anywhere — the absent dimension, wearing an implementation
    // failure's clothes, since every assert about pinning was reading an empty
    // string that no implementation could have filled.
    if (initGit) {
      final result = Process.runSync(
        'git',
        ['init', '--quiet', '--initial-branch=main', root.path],
      );
      if (result.exitCode != 0) {
        throw ProcessException('git', ['init', root.path], '${result.stderr}');
      }
    }
  }

  /// A site whose root lies in no repository at all — the one case a real
  /// `git init` must be withheld rather than granted, since a place outside
  /// any repository is a real, distinct condition and not an absence of
  /// setup.
  factory Site.loose([String label = 'site']) => Site(label, null, false);

  late final Directory root;
  final Git git;

  /// Runs [body] with this site's port installed as the ambient one.
  R run<R>(R Function() body) => runWithGit(git, body);

  /// Runs an asynchronous [body] with this site's port installed.
  Future<R> runAsync<R>(Future<R> Function() body) =>
      runWithGitAsync(git, body);

  /// A nested place inside this one — the tree name resolution walks up.
  Directory nested(String name) {
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    Directory('${dir.path}/.place').createSync(recursive: true);
    return dir;
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
