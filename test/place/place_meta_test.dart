import 'package:bentos_userland/src/place/model/place_meta.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PlaceMeta.load', () {
    test('parses name/description/owner from .place/place.yaml', () {
      final hab = Habitat();
      final root = hab.place(
        '/hq/cto',
        yaml: 'name: CTO Office\ndescription: engineering\nowner: john\n',
      );
      final meta = PlaceMeta.load(root, hab.fs);
      expect(meta.name, 'CTO Office');
      expect(meta.description, 'engineering');
      expect(meta.owner, 'john');
      expect(meta.warning, isNull);
    });

    test('.place/ with no place.yaml yields empty defaults, no warning', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto');
      final meta = PlaceMeta.load(root, hab.fs);
      expect(meta.name, isNull);
      expect(meta.warning, isNull);
    });

    test('malformed yaml degrades to defaults with a surfaced warning', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto', yaml: 'name: broken: here: bad\n');
      final meta = PlaceMeta.load(root, hab.fs);
      expect(meta.name, isNull);
      expect(meta.warning, isNotNull);
      expect(meta.warning, contains('/hq/cto/.place/place.yaml'));
    });

    test('empty fields degrade to null', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto', yaml: 'name:\ndescription: x\n');
      final meta = PlaceMeta.load(root, hab.fs);
      expect(meta.name, isNull);
      expect(meta.description, 'x');
    });
  });
}
