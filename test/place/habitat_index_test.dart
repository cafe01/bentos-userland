import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('HabitatIndex.scan', () {
    PlaceResolver resolverFor(Habitat hab) =>
        PlaceResolver(fs: hab.fs, home: hab.home);

    test('one scan finds every marked place', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      hab.place('/home/john/university/rust');
      final index = HabitatIndex.scan(resolverFor(hab));
      final paths = index.places.map((p) => p.root.path).toSet();
      expect(paths, containsAll(<String>[
        '/home/john/hq',
        '/home/john/hq/cto',
        '/home/john/university/rust',
      ]));
    });

    test('the implicit terminals materialize even markerless', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final index = HabitatIndex.scan(resolverFor(hab));
      final paths = index.places.map((p) => p.root.path).toSet();
      expect(paths, containsAll(<String>['/', hab.home]));
      expect(index.root.place.root.path, '/');
    });

    test('a directory carrying no .place/ never appears as a place', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/plain');
      final index = HabitatIndex.scan(resolverFor(hab));
      final paths = index.places.map((p) => p.root.path).toSet();
      expect(paths, isNot(contains('/home/john/hq/plain')));
    });

    test('nesting matches the resolver — child folds under nearest place ancestor', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/wing'); // unmarked intermediate
      hab.place('/home/john/hq/wing/cto');
      final index = HabitatIndex.scan(resolverFor(hab));
      final hq = index.places.firstWhere((p) => p.root.path == '/home/john/hq');
      final hqNode = index.nodeFor(hq)!;
      expect(
        hqNode.children.map((n) => n.place.root.path),
        contains('/home/john/hq/wing/cto'),
      );
    });

    test('children are sorted by name', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/zeta');
      hab.place('/home/john/hq/alpha');
      final index = HabitatIndex.scan(resolverFor(hab));
      final hq = index.places.firstWhere((p) => p.root.path == '/home/john/hq');
      expect(
        index.nodeFor(hq)!.children.map((n) => n.place.name),
        ['alpha', 'zeta'],
      );
    });
  });
}
