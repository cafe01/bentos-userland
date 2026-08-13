import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;

import '../git/fake_git.dart';

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

/// A hermetic site: a real directory marked as a place, with a [FakeGit]
/// standing in for the substrate.
///
/// Real directories rather than a memory filesystem, because worktrees are real
/// files by definition and the port's own verbs write them. What is faked is
/// the one thing `IOOverrides` cannot reach — the subprocess.
final class Site {
  /// [git] defaults to a private port; passed explicitly it lets two sites
  /// share one substrate, the way a source and its installer share one disk.
  Site([String label = 'site', FakeGit? git])
      : git = git ?? FakeGit() {
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
    this.git.workTrees.add(root.path);
  }

  late final Directory root;
  final FakeGit git;

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
