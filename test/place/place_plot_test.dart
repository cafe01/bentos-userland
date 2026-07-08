import 'dart:io';

import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place.plot', () {
    test('returns an opaque Directory, not a Place', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final result = Place('/hq').plot('mem');
        expect(result, isA<Directory>(), reason: 'plot returns a bare Directory');
        expect(result, isNot(isA<Place>()), reason: 'a plot is not itself a place');
      });
    });

    test('creates nothing', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final plot = Place('/hq').plot('mem');
        expect(plot.existsSync(), isFalse, reason: 'plot() is pure path law, no IO side effect');
      });
    });

    test('same plot path from handles anchored anywhere inside the place', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/nested/deep').createSync(recursive: true);
        final a = Place('/hq').plot('mem');
        final b = Place('/hq/nested/deep').plot('mem');
        expect(a.path, b.path, reason: 'plot path is keyed by referent, not anchor');
      });
    });

    test('different namespaces yield different paths', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        final place = Place('/hq');
        expect(place.plot('mem').path, isNot(place.plot('tx').path),
            reason: 'distinct namespaces are distinct plots');
      });
    });

    for (final bad in ['', 'a/b', r'a\b', '.', '..']) {
      test('invalid namespace "$bad" throws ArgumentError', () {
        runInMemoryFs((fs) {
          fs.directory('/hq/.place').createSync(recursive: true);
          expect(() => Place('/hq').plot(bad), throwsArgumentError,
              reason: 'namespace must be a single path segment');
        });
      });
    }

    test('plots enumerates exactly the namespaces holding ground', () {
      runInMemoryFs((fs) {
        // SETUP:
        final place = Place('/hq');
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory(place.plot('mem').path).createSync(recursive: true);
        fs.directory(place.plot('tx').path).createSync(recursive: true);
        // VERIFY:
        expect(place.plots.toSet(), {'mem', 'tx'}, reason: 'plots lists tenants that materialized');
      });
    });

    test('empty list for a place with no grants', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        expect(Place('/hq').plots, isEmpty, reason: 'no tenant has written yet');
      });
    });

    test('empty list for an implicit place', () {
      runInMemoryFs((fs) {
        expect(Place('/').plots, isEmpty, reason: 'implicit places have no grants either');
      });
    });
  });
}
