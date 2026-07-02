import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/minimap.dart';
import 'package:bentos_userland/src/place/place_resolver.dart';
import 'package:bentos_userland/src/place/render/info_render.dart';
import 'package:bentos_userland/src/place/render/minimap_render.dart';
import 'package:bentos_userland/src/place/render/tree_render.dart';
import 'package:bentos_userland/src/place/render/who_render.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  PlaceResolver resolverFor(Habitat hab) =>
      PlaceResolver(fs: hab.fs, home: hab.home);

  group('TreeRender', () {
    test('full expansion with descriptions; -t drops them', () {
      final hab = Habitat();
      hab.place('/home/john/hq', yaml: 'name: hq\ndescription: the wing\n');
      hab.place('/home/john/hq/cto', yaml: 'description: engineering\n');
      final index = HabitatIndex.scan(resolverFor(hab));
      final node = index.nodeFor(resolverFor(hab).enclosing('/home/john/hq'))!;

      final full = TreeRender().render(node);
      expect(full, contains('— the wing'));
      expect(full, contains('cto/   — engineering'));

      final topo = TreeRender(topologyOnly: true).render(node);
      expect(topo, isNot(contains('—')));
      expect(topo, contains('cto'));
    });
  });

  group('InfoRender', () {
    test('prints name, description, owner', () {
      final hab = Habitat();
      hab.place('/home/john/cpo',
          yaml: 'name: cpo\ndescription: product doctrine\nowner: alfred\n');
      final place = resolverFor(hab).enclosing('/home/john/cpo');
      final card = const InfoRender().render(place);
      expect(card, contains('cpo  — product doctrine'));
      expect(card, contains('owner:  alfred'));
    });

    test('missing optional fields render without crashing', () {
      final hab = Habitat();
      hab.place('/home/john/bare');
      final place = resolverFor(hab).enclosing('/home/john/bare');
      final card = const InfoRender().render(place);
      expect(card, 'bare');
    });
  });

  group('WhoRender', () {
    test('lists inhabitants of the place', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/.place/mem/john');
      hab.dir('/home/john/hq/.place/tx/alfred/build');
      final place = resolverFor(hab).enclosing('/home/john/hq');
      expect(const WhoRender().render(place), 'here:   alfred, john');
    });

    test('--all adds ancestor-inherited, tagged @place', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.dir('/home/john/hq/.place/mem/alfred');
      hab.place('/home/john/hq/cto');
      hab.dir('/home/john/hq/cto/.place/mem/john');
      final place = resolverFor(hab).enclosing('/home/john/hq/cto');
      final out = const WhoRender().render(place, all: true);
      expect(out, contains('here:   john'));
      expect(out, contains('alfred@hq'));
    });

    test('an uninhabited place renders honestly, not an error', () {
      final hab = Habitat();
      hab.place('/home/john/empty');
      final place = resolverFor(hab).enclosing('/home/john/empty');
      expect(const WhoRender().render(place), 'here:   (nobody)');
    });
  });

  group('MinimapRender', () {
    test('renders the marker on the current node', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      hab.place('/home/john/hq/cto');
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq/cto');
      final map = const Minimap().build(index, current);
      final text = const MinimapRender().render(map);
      expect(text, contains(MinimapRender.marker));
      expect(text.split('\n').where((l) => l.contains('cto')).single,
          contains(MinimapRender.marker));
    });

    test('the machine root heads the map', () {
      final hab = Habitat();
      hab.place('/home/john/hq');
      final index = HabitatIndex.scan(resolverFor(hab));
      final current = resolverFor(hab).enclosing('/home/john/hq');
      final text = const MinimapRender().render(const Minimap().build(index, current));
      expect(text.split('\n').first, contains('(the machine)'));
    });
  });
}
