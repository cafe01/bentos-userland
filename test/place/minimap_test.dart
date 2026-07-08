import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/minimap.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  /// Flatten the map to the set of place paths that appear (expanded or bare).
  Set<String> visiblePaths(MinimapNode node) {
    final out = <String>{};
    void walk(MinimapNode n) {
      if (n.place != null) out.add(n.place!.root.path);
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
    return out;
  }

  MinimapNode? find(MinimapNode node, String path) {
    if (node.place?.root.path == path) return node;
    for (final c in node.children) {
      final hit = find(c, path);
      if (hit != null) return hit;
    }
    return null;
  }

  group('Minimap', () {
    test('the ancestor chain is always expanded and rooted at the machine', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        Place('/home/john/hq/cto/coreutils').create();
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/cto/coreutils');
        final map = const Minimap(radius: 0).build(index, current);

        expect(map.place!.root.path, '/', reason: 'rooted at the machine');
        final paths = visiblePaths(map);
        expect(paths, containsAll(<String>[
          '/',
          '/home/john',
          '/home/john/hq',
          '/home/john/hq/cto',
          '/home/john/hq/cto/coreutils',
        ]), reason: 'the whole spine is present even at radius 0');
      });
    });

    test('the marker sits on the current node and nowhere else', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/cto');
        final map = const Minimap().build(index, current);

        final marked = <String>[];
        void walk(MinimapNode n) {
          if (n.isCurrent) marked.add(n.place!.root.path);
          n.children.forEach(walk);
        }

        walk(map);
        expect(marked, ['/home/john/hq/cto']);
      });
    });

    test('a distant branch collapses to name/… with an inclusive count', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create(); // current lives here
        // A far branch off home with nested children.
        Place('/home/john/university').create();
        Place('/home/john/university/rust').create();
        Place('/home/john/university/cs').create();
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/cto');
        final map = const Minimap(radius: 1).build(index, current);

        final uni = find(map, '/home/john/university')!;
        expect(uni.collapsed, isTrue);
        expect(uni.subtreeCount, 3, reason: 'university + rust + cs, inclusive');
        expect(uni.children, isEmpty, reason: 'collapsed branches hide children');
      });
    });

    test('a distant leaf shows bare, never as name/… (1 place)', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        Place('/home/john/lonely').create(); // leaf, far from current
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/cto');
        final map = const Minimap(radius: 0).build(index, current);

        final lonely = find(map, '/home/john/lonely')!;
        expect(lonely.collapsed, isFalse);
      });
    });

    test('radius widens the expanded neighborhood', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create(); // current
        Place('/home/john/university').create();
        Place('/home/john/university/rust').create(); // 2 hops from hq via home
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq');

        final tight = const Minimap(radius: 1).build(index, current);
        expect(find(tight, '/home/john/university')!.collapsed, isTrue);

        final wide = const Minimap(radius: 3).build(index, current);
        expect(find(wide, '/home/john/university')!.collapsed, isFalse);
        expect(visiblePaths(wide), contains('/home/john/university/rust'));
      });
    });

    test('long sibling lists truncate to +N more, keeping the spine visible', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        for (final n in ['a', 'b', 'c', 'd', 'e', 'f', 'target']) {
          Place('/home/john/hq/$n').create();
        }
        Place('/home/john/hq/target/deep').create(); // current under a late sibling
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/target/deep');
        final map = const Minimap(radius: 1, siblingLimit: 4).build(index, current);

        final hq = find(map, '/home/john/hq')!;
        final more = hq.children.where((c) => c.isMore).toList();
        expect(more.single.moreCount, greaterThan(0));
        // The spine-bearing child survives the truncation.
        expect(
          hq.children.any((c) => c.place?.root.path == '/home/john/hq/target'),
          isTrue,
        );
      });
    });
  });
}
