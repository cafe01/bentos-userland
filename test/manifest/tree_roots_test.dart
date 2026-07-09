import 'dart:io';

import 'package:bentos_userland/src/manifest/path_resolver.dart';
import 'package:bentos_userland/src/manifest/tree_roots.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

/// Make a directory (recursive) — lands on the hermetic in-memory fs when
/// called inside `runInMemoryFs`.
void _mkdir(String path) => Directory(path).createSync(recursive: true);

/// Mark [dir] as a place.
void _place(String dir) => _mkdir('$dir/.place');

/// Seed a particle file for FQDN `foo.bar`-style shadowing tests.
void _seed(String treeRoot, String relPath, String content) {
  final file = File('$treeRoot/$relPath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  group('resolveTreeRoots — explicit BENTOS_TREE_PATH first', () {
    test('single explicit root, verbatim, existence NOT checked', () {
      runInMemoryFs((fs) {
        // SETUP: env points at a root that does not exist on the fs.
        final roots = resolveTreeRoots({'BENTOS_TREE_PATH': '/explicit'});
        // VERIFY: an explicit root is the caller's assertion — kept regardless.
        expect(roots, ['/explicit']);
      });
    });

    test('multiple explicit roots split on colon, order preserved, empties dropped', () {
      runInMemoryFs((fs) {
        final roots = resolveTreeRoots({'BENTOS_TREE_PATH': '/a::/b:'});
        expect(roots, ['/a', '/b']);
      });
    });

    test('absent / empty BENTOS_TREE_PATH contributes no explicit root', () {
      runInMemoryFs((fs) {
        expect(resolveTreeRoots(const {}), isEmpty);
        expect(resolveTreeRoots({'BENTOS_TREE_PATH': ''}), isEmpty);
      });
    });
  });

  group('resolveTreeRoots — spatial tier: the referent place itself', () {
    test('self-inclusion: the enclosing place\'s own tree is found (the .ancestors-excludes-self regression guard)', () {
      runInMemoryFs((fs) {
        // SETUP: /work is a marked place carrying a tree; cwd is INSIDE it.
        _place('/work');
        _mkdir('/work/.bentos/tree');
        _mkdir('/work/a/b');
        fs.currentDirectory = '/work/a/b';
        // VERIFY: the referent contributes — Place.ancestors alone would drop it.
        expect(resolveTreeRoots(const {}), ['/work/.bentos/tree']);
      });
    });

    test('found when cwd IS the place root', () {
      runInMemoryFs((fs) {
        _place('/work');
        _mkdir('/work/.bentos/tree');
        fs.currentDirectory = '/work';
        expect(resolveTreeRoots(const {}), ['/work/.bentos/tree']);
      });
    });

    test('places-only tightening: a tree at an UNMARKED directory is not discovered', () {
      runInMemoryFs((fs) {
        // SETUP: /proj has a tree but no .place marker — a spatial void.
        _mkdir('/proj/.bentos/tree');
        fs.currentDirectory = '/proj';
        // VERIFY: .bentos/tree is payload at a place, never a marker of its own.
        expect(resolveTreeRoots(const {}), isEmpty);
      });
    });

    test('place without a tree contributes nothing (only-when-exists)', () {
      runInMemoryFs((fs) {
        _place('/work');
        fs.currentDirectory = '/work';
        expect(resolveTreeRoots(const {}), isEmpty);
      });
    });
  });

  group('resolveTreeRoots — nested-place cascade', () {
    test('inner AND outer place trees both contribute, nearest first', () {
      runInMemoryFs((fs) {
        _place('/hq');
        _mkdir('/hq/.bentos/tree');
        _place('/hq/team');
        _mkdir('/hq/team/.bentos/tree');
        _mkdir('/hq/team/deep');
        fs.currentDirectory = '/hq/team/deep';
        expect(resolveTreeRoots(const {}), [
          '/hq/team/.bentos/tree',
          '/hq/.bentos/tree',
        ]);
      });
    });

    test('per-FQDN nearest-wins shadowing through PathResolver, outer reachable for what the inner lacks', () {
      runInMemoryFs((fs) {
        // SETUP: both trees carry shared.atom; only the outer carries outer.atom.
        _place('/hq');
        _mkdir('/hq/.bentos/tree');
        _place('/hq/team');
        _mkdir('/hq/team/.bentos/tree');
        _seed('/hq/team/.bentos/tree', 'atom/shared/shared.xml', '<inner/>');
        _seed('/hq/.bentos/tree', 'atom/shared/shared.xml', '<outer/>');
        _seed('/hq/.bentos/tree', 'atom/outer/outer.xml', '<only-outer/>');
        fs.currentDirectory = '/hq/team';
        final roots = resolveTreeRoots(const {});
        final resolver = PathResolver(fs, roots);
        // VERIFY: nearest wins per FQDN…
        expect(resolver.resolve('shared.atom', '/hq/team')?.content, '<inner/>');
        // …and the outer tree is reachable for FQDNs the inner lacks — the
        // cascade, not the old at-most-one project root.
        expect(resolver.resolve('outer.atom', '/hq/team')?.content, '<only-outer/>');
      });
    });
  });

  group('resolveTreeRoots — home as the implicit place in the chain', () {
    test('\$HOME/.bentos/tree falls out of the ancestor chain, after nearer places', () {
      runInMemoryFs((fs) {
        // runInMemoryFs installs /home/john as the ambient home.
        _mkdir('/home/john/.bentos/tree');
        _place('/home/john/proj');
        _mkdir('/home/john/proj/.bentos/tree');
        fs.currentDirectory = '/home/john/proj';
        expect(resolveTreeRoots(const {}), [
          '/home/john/proj/.bentos/tree',
          '/home/john/.bentos/tree',
        ]);
      });
    });

    test('cwd at home: the home tree is the first and only implicit root', () {
      runInMemoryFs((fs) {
        _mkdir('/home/john/.bentos/tree');
        expect(resolveTreeRoots(const {}), ['/home/john/.bentos/tree']);
      });
    });

    test('home without a tree contributes nothing', () {
      runInMemoryFs((fs) {
        expect(resolveTreeRoots(const {}), isEmpty);
      });
    });
  });

  group('resolveTreeRoots — machine-root terminal', () {
    test('/.bentos/tree is the last tier when it exists', () {
      runInMemoryFs((fs) {
        _mkdir('/.bentos/tree');
        _mkdir('/home/john/.bentos/tree');
        // cwd is home (runInMemoryFs default).
        expect(resolveTreeRoots(const {}), [
          '/home/john/.bentos/tree',
          '/.bentos/tree',
        ]);
      });
    });
  });

  group('resolveTreeRoots — full ordering: explicit, then spatial nearest-first', () {
    test('explicit roots prepended before the whole spatial cascade', () {
      runInMemoryFs((fs) {
        _mkdir('/home/john/.bentos/tree');
        _place('/home/john/work');
        _mkdir('/home/john/work/.bentos/tree');
        _mkdir('/home/john/work/sub');
        fs.currentDirectory = '/home/john/work/sub';
        final roots = resolveTreeRoots({'BENTOS_TREE_PATH': '/explicit1:/explicit2'});
        expect(roots, [
          '/explicit1',
          '/explicit2',
          '/home/john/work/.bentos/tree',
          '/home/john/.bentos/tree',
        ]);
      });
    });
  });
}
