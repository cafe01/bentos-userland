import 'package:file/memory.dart';
import 'package:bentos_userland/src/manifest/tree_roots.dart';
import 'package:test/test.dart';

/// Make a directory at [path] in [fs] (recursive).
void _mkdir(MemoryFileSystem fs, String path) =>
    fs.directory(path).createSync(recursive: true);

void main() {
  group('resolveTreeRoots — explicit BENTOS_TREE_PATH first', () {
    test('single explicit root, verbatim, existence NOT checked', () {
      // SETUP: env points at a root that does not exist on the fs.
      final fs = MemoryFileSystem();
      final roots = resolveTreeRoots(fs, '/work', {'BENTOS_TREE_PATH': '/explicit'});
      // VERIFY: an explicit root is the caller's assertion — kept regardless.
      expect(roots, ['/explicit']);
    });

    test('multiple explicit roots split on colon, order preserved, empties dropped', () {
      final fs = MemoryFileSystem();
      final roots = resolveTreeRoots(fs, '/work', {'BENTOS_TREE_PATH': '/a::/b:'});
      expect(roots, ['/a', '/b']);
    });

    test('absent / empty BENTOS_TREE_PATH contributes no explicit root', () {
      final fs = MemoryFileSystem();
      expect(resolveTreeRoots(fs, '/work', const {}), isEmpty);
      expect(resolveTreeRoots(fs, '/work', {'BENTOS_TREE_PATH': ''}), isEmpty);
    });
  });

  group('resolveTreeRoots — implicit PROJECT root (walk-up), appended', () {
    test('discovers .bentos/tree in the cwd itself', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/work/.bentos/tree');
      expect(resolveTreeRoots(fs, '/work', const {}), ['/work/.bentos/tree']);
    });

    test('walks UP from a subdirectory to the nearest .bentos/tree', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/work/.bentos/tree');
      final roots = resolveTreeRoots(fs, '/work/a/b/c', const {});
      expect(roots, ['/work/.bentos/tree']);
    });

    test('nearest ancestor wins — at most one project root', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/work/.bentos/tree');
      _mkdir(fs, '/work/inner/.bentos/tree');
      final roots = resolveTreeRoots(fs, '/work/inner/deep', const {});
      expect(roots, ['/work/inner/.bentos/tree']);
    });

    test('no .bentos/tree anywhere up the chain → no project root', () {
      final fs = MemoryFileSystem();
      expect(resolveTreeRoots(fs, '/work/a/b', const {}), isEmpty);
    });
  });

  group('resolveTreeRoots — implicit USER root, appended', () {
    test('appends \$HOME/.bentos/tree when it exists', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/home/cafe/.bentos/tree');
      final roots = resolveTreeRoots(fs, '/work', {'HOME': '/home/cafe'});
      expect(roots, ['/home/cafe/.bentos/tree']);
    });

    test('omits the user root when the directory is absent', () {
      final fs = MemoryFileSystem();
      expect(resolveTreeRoots(fs, '/work', {'HOME': '/home/cafe'}), isEmpty);
    });

    test('omits the user root when HOME is unset', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/home/cafe/.bentos/tree');
      expect(resolveTreeRoots(fs, '/work', const {}), isEmpty);
    });
  });

  group('resolveTreeRoots — full ordering: explicit, then project, then user', () {
    test('all three present, appended in that exact order', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/work/.bentos/tree');
      _mkdir(fs, '/home/cafe/.bentos/tree');
      final roots = resolveTreeRoots(fs, '/work/sub', {
        'BENTOS_TREE_PATH': '/explicit1:/explicit2',
        'HOME': '/home/cafe',
      });
      expect(roots, [
        '/explicit1',
        '/explicit2',
        '/work/.bentos/tree',
        '/home/cafe/.bentos/tree',
      ]);
    });

    test('implicit defaults present even with no explicit roots', () {
      final fs = MemoryFileSystem();
      _mkdir(fs, '/work/.bentos/tree');
      _mkdir(fs, '/home/cafe/.bentos/tree');
      final roots = resolveTreeRoots(fs, '/work', {'HOME': '/home/cafe'});
      expect(roots, ['/work/.bentos/tree', '/home/cafe/.bentos/tree']);
    });
  });
}
