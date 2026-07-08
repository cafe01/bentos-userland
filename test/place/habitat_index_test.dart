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
  });
}
