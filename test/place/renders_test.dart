import 'package:bentos_userland/src/place/habitat_index.dart';
import 'package:bentos_userland/src/place/minimap.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/place/render/info_render.dart';
import 'package:bentos_userland/src/place/render/minimap_render.dart';
import 'package:bentos_userland/src/place/render/tree_render.dart';
import 'package:bentos_userland/src/place/render/who_render.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

void main() {
  group('TreeRender', () {
    test('full expansion with descriptions; -t drops them', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create(name: 'hq', description: 'the wing');
        Place('/home/john/hq/cto').create(description: 'engineering');
        final index = HabitatIndex.scan();
        final node = index.nodeFor(Place('/home/john/hq'))!;

        final full = TreeRender().render(node);
        expect(full, contains('— the wing'));
        expect(full, contains('cto/   — engineering'));

        final topo = TreeRender(topologyOnly: true).render(node);
        expect(topo, isNot(contains('—')));
        expect(topo, contains('cto'));
      });
    });
  });

  group('InfoRender', () {
    test('prints name, description, owner', () {
      runInMemoryFs((fs) {
        Place('/home/john/cpo')
            .create(name: 'cpo', description: 'product doctrine', owner: 'alfred');
        final place = Place('/home/john/cpo');
        final card = const InfoRender().render(place);
        expect(card, contains('cpo  — product doctrine'));
        expect(card, contains('owner:  alfred'));
      });
    });

    test('missing optional fields render without crashing', () {
      runInMemoryFs((fs) {
        Place('/home/john/bare').create();
        final place = Place('/home/john/bare');
        expect(const InfoRender().render(place), 'bare');
      });
    });
  });

  group('WhoRender', () {
    test('lists the tenants holding ground at the place', () {
      runInMemoryFs((fs) {
        final place = Place('/home/john/hq')..create();
        fs.directory(place.plot('mem').path).createSync(recursive: true);
        fs.directory(place.plot('tx').path).createSync(recursive: true);
        expect(const WhoRender().render(place), 'here:   mem, tx');
      });
    });

    test('--all adds ancestor-inherited, tagged @place', () {
      runInMemoryFs((fs) {
        final hq = Place('/home/john/hq')..create();
        fs.directory(hq.plot('mem').path).createSync(recursive: true);
        final cto = Place('/home/john/hq/cto')..create();
        fs.directory(cto.plot('tx').path).createSync(recursive: true);
        final out = const WhoRender().render(cto, all: true);
        expect(out, contains('here:   tx'));
        expect(out, contains('mem@hq'));
      });
    });

    test('an uninhabited place renders honestly, not an error', () {
      runInMemoryFs((fs) {
        final place = Place('/home/john/empty')..create();
        expect(const WhoRender().render(place), 'here:   (nobody)');
      });
    });
  });

  group('MinimapRender', () {
    test('renders the marker on the current node', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        Place('/home/john/hq/cto').create();
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq/cto');
        final map = const Minimap().build(index, current);
        final text = const MinimapRender().render(map);
        expect(text, contains(MinimapRender.marker));
        expect(text.split('\n').where((l) => l.contains('cto')).single,
            contains(MinimapRender.marker));
      });
    });

    test('the machine root heads the map', () {
      runInMemoryFs((fs) {
        Place('/home/john/hq').create();
        final index = HabitatIndex.scan();
        final current = Place('/home/john/hq');
        final text = const MinimapRender().render(const Minimap().build(index, current));
        expect(text.split('\n').first, contains('(the machine)'));
      });
    });
  });
}
