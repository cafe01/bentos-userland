import 'package:bentos_userland/src/place/place_init.dart';
import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:bentos_userland/src/place/residence.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PlaceInit', () {
    test('creates .place/ and writes place.yaml with the given fields', () {
      final hab = Habitat();
      hab.dir('/home/john/research/q09');
      final result = PlaceInit(hab.fs).run(
        '/home/john/research/q09',
        owner: 'alfred',
        desc: 'Memory substrate research',
      );
      expect(result.created, isTrue);
      final yaml = Residence.metaFile(
        hab.fs.directory('/home/john/research/q09'),
        hab.fs,
      ).readAsStringSync();
      expect(yaml, contains('name: q09'), reason: 'name defaults to the directory');
      expect(yaml, contains('owner: alfred'));
      expect(yaml, contains('description: Memory substrate research'));

      // The new place is resolvable.
      final place =
          PlaceResolver(fs: hab.fs, home: hab.home).enclosing('/home/john/research/q09');
      expect(place.isImplicit, isFalse);
      expect(place.owner, 'alfred');
    });

    test('an explicit --name overrides the directory default', () {
      final hab = Habitat();
      hab.dir('/home/john/x');
      PlaceInit(hab.fs).run('/home/john/x', name: 'Crucible');
      final place = PlaceResolver(fs: hab.fs, home: hab.home).enclosing('/home/john/x');
      expect(place.name, 'Crucible');
    });

    test('a pre-existing place is reported cleanly, never clobbered', () {
      final hab = Habitat();
      hab.place('/home/john/hq', yaml: 'name: original\n');
      final result = PlaceInit(hab.fs).run('/home/john/hq', name: 'usurper');
      expect(result.created, isFalse);
      expect(result.message, contains('already initialized'));
      final place = PlaceResolver(fs: hab.fs, home: hab.home).enclosing('/home/john/hq');
      expect(place.name, 'original', reason: 'the existing yaml is untouched');
    });
  });
}
