import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PlaceResolver.enclosing', () {
    test('finds the nearest enclosing .place walking up', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/cto/coreutils');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/home/john/hq/cto/coreutils');
      expect(place.root.path, '/home/john/hq');
      expect(place.isImplicit, isFalse);
    });

    test('nearest wins over an outer marked place', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      expect(r.enclosing('/home/john/hq/cto/x').root.path, '/home/john/hq/cto');
    });

    test('a legacy bare place.yaml (no .place/) is not a marker', () {
      final hab = Habitat();
      final legacy = hab.dir('/home/john/legacy');
      hab.fs.file('/home/john/legacy/place.yaml').writeAsStringSync('name: old\n');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      // Falls through to implicit home, not the legacy dir.
      expect(r.enclosing(legacy.path).root.path, hab.home);
      expect(r.enclosing(legacy.path).isImplicit, isTrue);
    });

    test('unmarked path under home resolves to implicit home', () {
      final hab = Habitat();
      hab.dir('/home/john/projects/x');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/home/john/projects/x');
      expect(place.root.path, hab.home);
      expect(place.isImplicit, isTrue);
    });

    test('unmarked path above home resolves to the implicit machine root', () {
      final hab = Habitat();
      hab.dir('/usr/local');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/usr/local');
      expect(place.root.path, '/');
      expect(place.isImplicit, isTrue);
    });

    test('a marked home is a real place, not implicit', () {
      final hab = Habitat();
      hab.place('/home/john');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/home/john/x');
      expect(place.root.path, hab.home);
      expect(place.isImplicit, isFalse);
    });
  });

  group('PlaceResolver.ancestorsOf (place.ancestors)', () {
    test('ordered nearest → outermost, skipping unmarked intermediates', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/wing'); // unmarked intermediate
      hab.place('/home/john/hq/wing/cto');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final chain = r.enclosing('/home/john/hq/wing/cto/x').ancestors;
      expect(
        chain.map((p) => p.root.path),
        ['/home/john/hq', '/home/john', '/'],
      );
    });

    test('excludes the place itself', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/home/john/hq');
      expect(place.ancestors.map((p) => p.root.path), ['/home/john', '/']);
    });

    test('includes implicit home when the place sits under home', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final chain = r.enclosing('/home/john/hq').ancestors;
      expect(chain.any((p) => p.root.path == hab.home && p.isImplicit), isTrue);
    });

    test('always terminates at the machine root', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      expect(r.enclosing('/home/john/hq').ancestors.last.root.path, '/');
    });

    test('a place at the machine root has an empty chain', () {
      final hab = Habitat();
      hab.place('/');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      expect(r.enclosing('/').ancestors, isEmpty);
    });
  });

  group('Place accessors', () {
    test('name defaults to the directory when metadata absent', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      expect(r.enclosing('/home/john/hq').name, 'hq');
    });

    test('name comes from metadata when present', () {
      final hab = Habitat();
      hab.place('/home/john/hq', yaml: 'name: Headquarters\n');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      expect(r.enclosing('/home/john/hq').name, 'Headquarters');
    });

    test('memoryRoot/txRoot hand back residence handles', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final r = PlaceResolver(fs: hab.fs, home: hab.home);
      final place = r.enclosing('/home/john/hq');
      expect(place.memoryRoot('john').path, '/home/john/hq/.place/mem/john');
      expect(place.txRoot('john', 'build').path,
          '/home/john/hq/.place/tx/john/build');
    });
  });
}
