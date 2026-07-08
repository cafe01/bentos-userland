import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place metadata', () {
    test('parses name/description/owner from .place/place.yaml', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.file('/hq/.place/place.yaml')
            .writeAsStringSync('name: CTO Office\ndescription: engineering\nowner: john\n');
        // BEHAVIOR:
        final place = Place('/hq');
        // VERIFY:
        expect(place.name, 'CTO Office', reason: 'name parsed from place.yaml');
        expect(place.description, 'engineering', reason: 'description parsed from place.yaml');
        expect(place.owner, 'john', reason: 'owner parsed from place.yaml');
      });
    });

    test('name defaults to the directory name when absent', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/cto/.place').createSync(recursive: true);
        expect(Place('/hq/cto').name, 'cto', reason: 'no name field falls back to basename');
      });
    });

    test('name defaults to the path for /', () {
      runInMemoryFs((fs) {
        expect(Place('/').name, '/', reason: 'machine root has no basename, falls back to path');
      });
    });

    test('malformed yaml degrades to defaults, never a crash', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.file('/hq/.place/place.yaml').writeAsStringSync('name: broken: here: bad\n');
        final place = Place('/hq');
        expect(() => place.name, returnsNormally, reason: 'malformed yaml must not throw');
        expect(place.name, 'hq', reason: 'malformed metadata degrades to the directory name');
      });
    });

    test('a .place/ with no place.yaml is still a place', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final place = Place('/hq');
        expect(place.isImplicit, isFalse, reason: 'the marker alone makes it a place');
        expect(place.name, 'hq', reason: 'no metadata falls back to directory name');
      });
    });
  });
}
