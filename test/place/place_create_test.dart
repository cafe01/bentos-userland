import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place.create', () {
    test('marks the anchor, not the referent', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/nested').createSync(recursive: true);
        // BEHAVIOR:
        final created = Place('/hq/nested').create();
        // VERIFY:
        expect(created.root.path, '/hq/nested', reason: 'create marks the anchor itself');
        expect(fs.directory('/hq/nested/.place').existsSync(), isTrue,
            reason: '.place/ is created at the anchor');
      });
    });

    test('writes place.yaml with the given fields', () {
      runInMemoryFs((fs) {
        Place('/hq/nested').create(name: 'HQ', description: 'desc', owner: 'john');
        expect(fs.file('/hq/nested/.place/place.yaml').existsSync(), isTrue,
            reason: 'place.yaml is written on create');
        final place = Place('/hq/nested');
        expect(place.name, 'HQ', reason: 'name field round-trips');
        expect(place.description, 'desc', reason: 'description field round-trips');
        expect(place.owner, 'john', reason: 'owner field round-trips');
      });
    });

    test('name defaults to the directory name', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/nested').createSync(recursive: true);
        Place('/hq/nested').create();
        expect(Place('/hq/nested').name, 'nested',
            reason: 'unnamed create defaults to the directory basename');
      });
    });

    test('a pre-existing marker is never clobbered', () {
      runInMemoryFs((fs) {
        // SETUP:
        Place('/hq/nested').create(name: 'Original');
        // BEHAVIOR:
        Place('/hq/nested').create(name: 'Overwrite Attempt');
        // VERIFY:
        expect(Place('/hq/nested').name, 'Original',
            reason: 'second create() must not clobber existing metadata');
      });
    });

    test('the created place is immediately resolvable, not implicit', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/nested').createSync(recursive: true);
        Place('/hq/nested').create();
        final fresh = Place('/hq/nested');
        expect(fresh.root.path, '/hq/nested', reason: 'a fresh handle resolves at the anchor');
        expect(fresh.isImplicit, isFalse, reason: 'a created place is never implicit');
      });
    });
  });
}
