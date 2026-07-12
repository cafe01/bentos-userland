import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('HabitatIndex.scan', () {
    test('one scan finds every marked place', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        Place('/home/john/university/rust').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, containsAll(<String>[
          '/home/john/hq',
          '/home/john/hq/cto',
          '/home/john/university/rust',
        ]));
      });
    });

    test('the implicit terminals materialize even markerless', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, containsAll(<String>['/', '/home/john']));
        expect(index.root.place.root.path, '/');
      });
    });

    test('a directory carrying no .place/ never appears as a place', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        fs.directory('/home/john/hq/plain').createSync(recursive: true);
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/hq/plain')));
      });
    });

    test('nesting matches resolution — child folds under nearest place ancestor', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        fs.directory('/home/john/hq/wing').createSync(recursive: true); // unmarked
        Place('/home/john/hq/wing/cto').create();
        final index = HabitatIndex.scan();
        final hq = index.places.firstWhere((p) => p.root.path == '/home/john/hq');
        final hqNode = index.nodeFor(hq)!;
        expect(
          hqNode.children.map((n) => n.place.root.path),
          contains('/home/john/hq/wing/cto'),
        );
      });
    });

    test('children are sorted by name', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/zeta').create();
        Place('/home/john/hq/alpha').create();
        final index = HabitatIndex.scan();
        final hq = index.places.firstWhere((p) => p.root.path == '/home/john/hq');
        expect(
          index.nodeFor(hq)!.children.map((n) => n.place.name),
          ['alpha', 'zeta'],
        );
      });
    });

    test('a root .gitignore prunes a whole-directory pattern from descent', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        fs.file('/home/john/hq/.gitignore').createSync(recursive: true);
        fs.file('/home/john/hq/.gitignore').writeAsStringSync('dist\ntarget/\n');
        Place('/home/john/hq/dist/nested').create();
        Place('/home/john/hq/target/nested').create();
        Place('/home/john/hq/kept').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/hq/dist/nested')));
        expect(paths, isNot(contains('/home/john/hq/target/nested')));
        expect(paths, contains('/home/john/hq/kept'));
      });
    });

    test('a nested .gitignore layers onto its ancestor, scoped to its own subtree', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/wing').create();
        fs.file('/home/john/hq/wing/.gitignore').createSync(recursive: true);
        fs.file('/home/john/hq/wing/.gitignore').writeAsStringSync('coverage\n');
        Place('/home/john/hq/wing/coverage/nested').create();
        // Same basename outside the nested .gitignore's scope is unaffected.
        Place('/home/john/hq/coverage/nested').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/hq/wing/coverage/nested')));
        expect(paths, contains('/home/john/hq/coverage/nested'));
      });
    });

    test('a glob pattern prunes matching directory names', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        fs.file('/home/john/hq/.gitignore').createSync(recursive: true);
        fs.file('/home/john/hq/.gitignore').writeAsStringSync('*.egg-info\n');
        Place('/home/john/hq/foo.egg-info/nested').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/hq/foo.egg-info/nested')));
      });
    });

    test('a negated pattern is not honored (pragmatic, not full fidelity)', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        fs.file('/home/john/hq/.gitignore').createSync(recursive: true);
        fs.file('/home/john/hq/.gitignore').writeAsStringSync('artifacts\n!artifacts\n');
        Place('/home/john/hq/artifacts/nested').create();
        final index = HabitatIndex.scan();
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/hq/artifacts/nested')));
      });
    });
  });

  group('HabitatIndex.neighborhood', () {
    test('roots at the topmost real place and grafts the implicit ancestors above', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        final index = HabitatIndex.neighborhood(Place('/home/john/hq/cto'));
        // The machine root heads the map; home and the habitat are present.
        expect(index.root.place.root.path, '/');
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, containsAll(<String>[
          '/', '/home/john', '/home/john/hq', '/home/john/hq/cto',
        ]));
      });
    });

    test('does not walk the home\'s sibling voids outside the habitat', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        // A sibling top-level place and a bulky unmarked void, both under home:
        // neither is under the habitat root, so neither is scanned in.
        Place('/home/john/university/rust').create();
        fs.directory('/home/john/sdk-dump/a/b/c').createSync(recursive: true);
        final index = HabitatIndex.neighborhood(Place('/home/john/hq/cto'));
        final paths = index.places.map((p) => p.root.path).toSet();
        expect(paths, isNot(contains('/home/john/university/rust')),
            reason: 'a sibling habitat is a different neighborhood, not scanned');
        expect(paths, isNot(contains('/home/john/university')));
      });
    });

    test('falls back to the resolved place when the spine carries no real place', () {
      runInMemoryFs((fs) {
        fs.directory('/home/john/projects/x').createSync(recursive: true);
        final index = HabitatIndex.neighborhood(Place('/home/john/projects/x'));
        // Never nowhere: the implicit home locates us, headed by the machine.
        expect(index.root.place.root.path, '/');
        expect(index.nodeFor(Place('/home/john/projects/x')), isNotNull);
      });
    });
  });
}
