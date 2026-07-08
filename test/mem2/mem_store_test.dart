import 'package:bentos_userland/src/mem2/mem_store.dart';
import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/model/mem_writer.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('MemStore — layout, cascade, shadow, write-target', () {
    MemStore storeAt(MemHabitat hab, String cwd) => MemStore(
          vantage: Place(cwd),
          entity: hab.entity,
          writer: MemWriter(hab.now),
        );

    test('reads and lists a page at a slash-topic, nested as folders', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq/cto');
        hab.seed('/hq/cto', 'agency/spawn', MemHabitat.page('procedural', '0.7', 'x'));
        final store = storeAt(hab, '/hq/cto');

        final page = store.readAt(store.vantage, 'agency/spawn');
        expect(page, isNotNull);
        expect(page!.topic, 'agency/spawn');
        expect(store.listAt(store.vantage).map((p) => p.topic), ['agency/spawn']);
      });
    });

    test('cascade merges vantage + ancestors, annotating origin', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq');
        hab.place('/hq/cto');
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
        hab.seed('/hq/cto', 'local', MemHabitat.page('episodic', '0.3', 'b'));
        final store = storeAt(hab, '/hq/cto');

        final topics = {for (final p in store.cascade()) p.topic: p.origin!.root.path};
        expect(topics['local'], '/hq/cto', reason: 'vantage page');
        expect(topics['founders'], '/hq', reason: 'inherited from ancestor');
      });
    });

    test('shared topic resolves nearest-wins, ancestor shadowed', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq');
        hab.place('/hq/cto');
        hab.seed('/hq', 'shared', MemHabitat.page('semantic', '0.5', 'ancestor'));
        hab.seed('/hq/cto', 'shared', MemHabitat.page('semantic', '0.9', 'nearer'));
        final store = storeAt(hab, '/hq/cto');

        final shared = store.cascade().where((p) => p.topic == 'shared').toList();
        expect(shared, hasLength(1), reason: 'ancestor shadowed');
        expect(shared.single.body, 'nearer');
        expect(shared.single.origin!.root.path, '/hq/cto');
      });
    });

    test('write-target: existing topic keeps its home place', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq');
        hab.place('/hq/cto');
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
        final store = storeAt(hab, '/hq/cto');
        expect(store.writeTargetFor('founders').root.path, '/hq',
            reason: 'replace lands where the page lives');
      });
    });

    test('write-target: new topic anchors at the vantage', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq');
        hab.place('/hq/cto');
        final store = storeAt(hab, '/hq/cto');
        expect(store.writeTargetFor('fresh').root.path, '/hq/cto');
      });
    });

    test('write round-trips a page through the resolved layout', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq/cto');
        final store = storeAt(hab, '/hq/cto');
        final landed = store.write('agency/spawn',
            type: MemType.procedural, attention: Attention.parse('0.7'), body: 'body');
        expect(landed.origin!.root.path, '/hq/cto');

        final back = store.readAt(store.vantage, 'agency/spawn');
        expect(back!.body, 'body');
        expect(back.fields.attention, Attention.parse('0.7'));
      });
    });

    test('replace of an inherited topic rewrites the ancestor in place', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq');
        hab.place('/hq/cto');
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'old'));
        final store = storeAt(hab, '/hq/cto');

        final landed = store.write('founders',
            type: MemType.semantic, attention: Attention.parse('1.0'), body: 'new');
        expect(landed.origin!.root.path, '/hq', reason: 'no local shadow created');

        final atVantage = store.readAt(store.vantage, 'founders');
        expect(atVantage, isNull, reason: 'nothing landed at the vantage');
        expect(store.readAt(Place('/hq'), 'founders')!.body, 'new');
      });
    });

    test('missing store lists empty, does not crash', () {
      runInMemoryFs((fs) {
        final hab = MemHabitat();
        hab.place('/hq/cto');
        final store = storeAt(hab, '/hq/cto');
        expect(store.listAt(store.vantage), isEmpty);
      });
    });
  });
}
