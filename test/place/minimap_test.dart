import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/minimap.dart';
import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  PlaceResolver resolverFor(Habitat hab) =>
      PlaceResolver(fs: hab.fs, home: hab.home);

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
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      hab.place('/home/john/hq/cto/coreutils');
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/cto/coreutils');
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

    test('the marker sits on the current node and nowhere else', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/cto');
      final map = const Minimap().build(index, current);

      final marked = <String>[];
      void walk(MinimapNode n) {
        if (n.isCurrent) marked.add(n.place!.root.path);
        n.children.forEach(walk);
      }

      walk(map);
      expect(marked, ['/home/john/hq/cto']);
    });

    test('a distant branch collapses to name/… with an inclusive count', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto'); // current lives here
      // A far branch off home with nested children.
      hab.place('/home/john/university');
      hab.place('/home/john/university/rust');
      hab.place('/home/john/university/cs');
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/cto');
      final map = const Minimap(radius: 1).build(index, current);

      final uni = find(map, '/home/john/university')!;
      expect(uni.collapsed, isTrue);
      expect(uni.subtreeCount, 3, reason: 'university + rust + cs, inclusive');
      expect(uni.children, isEmpty, reason: 'collapsed branches hide children');
    });

    test('a distant leaf shows bare, never as name/… (1 place)', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      hab.place('/home/john/lonely'); // leaf, far from current
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/cto');
      final map = const Minimap(radius: 0).build(index, current);

      final lonely = find(map, '/home/john/lonely')!;
      expect(lonely.collapsed, isFalse);
    });

    test('radius widens the expanded neighborhood', () {
      final hab = Habitat();
      hab.place('/home/john/hq'); // current
      hab.place('/home/john/university');
      hab.place('/home/john/university/rust'); // 2 hops from hq via home
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq');

      final tight = const Minimap(radius: 1).build(index, current);
      expect(find(tight, '/home/john/university')!.collapsed, isTrue);

      final wide = const Minimap(radius: 3).build(index, current);
      expect(find(wide, '/home/john/university')!.collapsed, isFalse);
      expect(visiblePaths(wide), contains('/home/john/university/rust'));
    });

    test('long sibling lists truncate to +N more, keeping the spine visible', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      for (final n in ['a', 'b', 'c', 'd', 'e', 'f', 'target']) {
        hab.place('/home/john/hq/$n');
      }
      hab.place('/home/john/hq/target/deep'); // current under a late sibling
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/target/deep');
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
}
