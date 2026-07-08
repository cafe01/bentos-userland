import 'dart:io';

import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place resolution', () {
    test('root finds the nearest enclosing .place walking up from the anchor', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/repo/.place').createSync(recursive: true);
        fs.directory('/repo/nested/deep').createSync(recursive: true);
        // BEHAVIOR:
        final place = Place('/repo/nested/deep');
        // VERIFY:
        expect(place.root.path, '/repo', reason: 'walk up finds nearest .place marker');
      });
    });

    test('a legacy bare place.yaml without .place is not a marker', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/repo/nested').createSync(recursive: true);
        fs.file('/repo/place.yaml').createSync(recursive: true);
        // BEHAVIOR:
        final place = Place('/repo/nested');
        // VERIFY:
        expect(place.root.path, isNot('/repo'),
            reason: 'bare place.yaml without .place/ does not mark a place');
      });
    });

    test('/ materializes as an implicit place when unmarked', () {
      runInMemoryFs((fs) {
        final place = Place('/');
        expect(place.root.path, '/', reason: 'machine root is the terminal referent');
        expect(place.isImplicit, isTrue, reason: 'unmarked root is implicit');
      });
    });

    test('home materializes as an implicit place when unmarked', () {
      runInMemoryFs((fs) {
        final place = Place('/home/john/docs');
        expect(place.root.path, '/home/john', reason: 'unmarked home is the referent');
        expect(place.isImplicit, isTrue, reason: 'unmarked home is implicit');
      });
    });

    test('isImplicit is false for a marked place', () {
      runInMemoryFs((fs) {
        fs.directory('/repo/.place').createSync(recursive: true);
        final place = Place('/repo');
        expect(place.isImplicit, isFalse, reason: 'a marked directory is not implicit');
      });
    });

    test('at / resolves to the machine itself, never nowhere', () {
      runInMemoryFs((fs) {
        final place = Place('/anywhere/deep/nested');
        expect(place.root.path, isNotEmpty, reason: 'resolution never fails');
      });
    });

    test('constructor performs no IO', () {
      runInMemoryFs((fs) {
        // SETUP: no seeding — path does not exist.
        // BEHAVIOR:
        final place = Place('/does/not/exist');
        // VERIFY: construction itself must not throw.
        expect(() => place, returnsNormally, reason: 'constructor is pure, zero IO');
      });
    });

    test('Place.current resolves the place enclosing the working directory', () {
      runInMemoryFs((fs) {
        fs.directory('/repo/.place').createSync(recursive: true);
        fs.directory('/repo/nested').createSync(recursive: true);
        Directory.current = '/repo/nested';
        final place = Place.current;
        expect(place.root.path, '/repo', reason: 'Place.current anchors at cwd');
      });
    });
  });
}
