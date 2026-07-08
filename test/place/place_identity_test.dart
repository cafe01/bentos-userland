import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('Place identity — anchor vs referent', () {
    test('two handles at different interior paths agree on root, name, ancestors', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/nested/deep').createSync(recursive: true);
        // BEHAVIOR:
        final a = Place('/hq');
        final b = Place('/hq/nested/deep');
        // VERIFY:
        expect(a.root.path, b.root.path, reason: 'same referent from different anchors');
        expect(a.name, b.name, reason: 'name is a referent property');
        expect(
          a.ancestors.map((p) => p.root.path).toList(),
          b.ancestors.map((p) => p.root.path).toList(),
          reason: 'ancestor chain is a referent property',
        );
      });
    });

    test('plot(ns) is the same path from both handles', () {
      runInMemoryFs((fs) {
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/nested/deep').createSync(recursive: true);
        final a = Place('/hq');
        final b = Place('/hq/nested/deep');
        expect(a.plot('mem').path, b.plot('mem').path,
            reason: 'plot is keyed by referent, not anchor');
      });
    });

    test('handles are live: create() on a nested unmarked anchor re-resolves root there', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/nested').createSync(recursive: true);
        // BEHAVIOR:
        final place = Place('/hq/nested');
        place.create();
        // VERIFY:
        expect(place.root.path, '/hq/nested',
            reason: 'the same handle observes its own create() on next read');
      });
    });

    test('handles are live: deleting the marker externally is observed on next read', () {
      runInMemoryFs((fs) {
        // SETUP:
        fs.directory('/hq/.place').createSync(recursive: true);
        fs.directory('/hq/nested').createSync(recursive: true);
        final place = Place('/hq/nested');
        expect(place.root.path, '/hq', reason: 'sanity: resolves to marked ancestor first');
        // BEHAVIOR:
        fs.directory('/hq/.place').deleteSync(recursive: true);
        // VERIFY:
        expect(place.root.path, isNot('/hq'),
            reason: 'existing handle climbs past the now-unmarked directory');
      });
    });
  });
}
