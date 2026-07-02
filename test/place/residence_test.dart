import 'package:bentos_userland/src/place/residence.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Residence — path law', () {
    final hab = Habitat();
    final root = hab.dir('/hq/cto');

    test('markerDir is <place>/.place', () {
      expect(Residence.markerDir(root, hab.fs).path, '/hq/cto/.place');
    });

    test('metaFile is <place>/.place/place.yaml', () {
      expect(Residence.metaFile(root, hab.fs).path, '/hq/cto/.place/place.yaml');
    });

    test('memoryRoot is <place>/.place/mem/<entity>', () {
      expect(
        Residence.memoryRoot(root, hab.fs, 'john').path,
        '/hq/cto/.place/mem/john',
      );
    });

    test('txRoot is <place>/.place/tx/<entity>/<scope>', () {
      expect(
        Residence.txRoot(root, hab.fs, 'john', 'build').path,
        '/hq/cto/.place/tx/john/build',
      );
    });

    test('resolvers create nothing on disk', () {
      Residence.memoryRoot(root, hab.fs, 'john');
      Residence.txRoot(root, hab.fs, 'john', 'build');
      expect(hab.fs.directory('/hq/cto/.place').existsSync(), isFalse);
    });
  });
}
