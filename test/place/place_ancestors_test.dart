import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place.ancestors', () {
    test('ordered nearest to outermost', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/dept/.place').createSync(recursive: true);
        fs.directory('/hq/dept/team/.place').createSync(recursive: true);
        // BEHAVIOR:
        final place = Place('/hq/dept/team');
        // VERIFY:
        expect(
          place.ancestors.map((p) => p.root.path).toList(),
          ['/hq/dept', '/hq', '/'],
          reason: 'nearest parent first, machine root last',
        );
      });
    });

    test('skips unmarked intermediate directories', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/unmarked/team/.place').createSync(recursive: true);
        final place = Place('/hq/unmarked/team');
        expect(
          place.ancestors.map((p) => p.root.path).toList(),
          isNot(contains('/hq/unmarked')),
          reason: 'unmarked intermediates are voids, never in the chain',
        );
      });
    });

    test('excludes the place itself', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final place = Place('/hq');
        expect(place.ancestors.map((p) => p.root.path), isNot(contains('/hq')),
            reason: 'ancestors are strictly above the referent');
      });
    });

    test('always terminates at the machine root', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final place = Place('/hq');
        expect(place.ancestors.last.root.path, '/',
            reason: 'the chain always bottoms out at the machine');
      });
    });

    test('includes the implicit home when the place sits under home', () {
      runInMemoryFs((fs) {
        fs.directory('/home/john/proj/.place').createSync(recursive: true);
        final place = Place('/home/john/proj');
        expect(
          place.ancestors.map((p) => p.root.path),
          contains('/home/john'),
          reason: 'implicit home is a real link in the chain',
        );
      });
    });

    test('a place at / has an empty chain', () {
      runInMemoryFs((fs) {
        final place = Place('/');
        expect(place.ancestors, isEmpty, reason: 'nothing sits above the machine root');
      });
    });

    test('parent is the chain\'s head', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/dept/.place').createSync(recursive: true);
        final place = Place('/hq/dept');
        expect(place.parent?.root.path, place.ancestors.first.root.path,
            reason: 'parent is ancestors.first');
      });
    });

    test('parent is null only at the machine root', () {
      runInMemoryFs((fs) {
        final place = Place('/');
        expect(place.parent, isNull, reason: 'the machine root has no parent');
      });
    });
  });
}
