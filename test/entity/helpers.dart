import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;

import '../git/fake_git.dart';

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

/// A hermetic site: a real directory marked as a place, with a [FakeGit]
/// standing in for the substrate.
///
/// Real directories rather than a memory filesystem, because worktrees are real
/// files by definition and the port's own verbs write them. What is faked is
/// the one thing `IOOverrides` cannot reach — the subprocess.
final class Site {
  Site([String label = 'site']) {
    // Resolved: a place answers with its canonical root, and the system temp is
    // reached through a link on some machines. A site that kept the link's
    // spelling would have its assertions comparing two vocabularies of one path.
    root = Directory(Directory.systemTemp
        .createTempSync('entity_$label')
        .resolveSymbolicLinksSync());
    Directory('${root.path}/.place').createSync(recursive: true);
    File('${root.path}/.place/place.yaml').writeAsStringSync('name: $label\n');
  }

  late final Directory root;
  final FakeGit git = FakeGit();

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
