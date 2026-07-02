import 'package:bentos_userland/src/place/inhabitants.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Inhabitants.of', () {
    test('enumerates the union of mem/ and tx/ entity namespaces, sorted', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto');
      hab.dir('/hq/cto/.place/mem/john');
      hab.dir('/hq/cto/.place/tx/alfred/build');
      hab.dir('/hq/cto/.place/tx/john/review');
      expect(Inhabitants.of(root, hab.fs), ['alfred', 'john']);
    });

    test('an entity with several scopes appears once (entity-level only)', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto');
      hab.dir('/hq/cto/.place/tx/john/build');
      hab.dir('/hq/cto/.place/tx/john/review');
      hab.dir('/hq/cto/.place/mem/john');
      expect(Inhabitants.of(root, hab.fs), ['john']);
    });

    test('an empty residence enumerates empty, never errors', () {
      final hab = Habitat();
      final root = hab.place('/hq/cto');
      expect(Inhabitants.of(root, hab.fs), isEmpty);
    });

    test('a place with no .place/ at all enumerates empty', () {
      final hab = Habitat();
      final root = hab.dir('/hq/plain');
      expect(Inhabitants.of(root, hab.fs), isEmpty);
    });
  });
}
