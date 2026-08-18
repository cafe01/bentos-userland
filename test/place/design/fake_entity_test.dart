// The fake is the contract's second implementation: the laws the suite leans
// on must hold in the fake itself, or a green place would prove nothing.
import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart' show writeIn;
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  test('born, act, land: the tree lands whole, the history records actor, date, sentence and title', () async {
    await runPlace(gate, (fs) async {
      final c = await gate.author(manifestOf('x.place', kind: 'place'), at: Directory('/home/john/x'), plot: Directory('/home/john/x/.place/place'), actor: tester) as FakeCopy;
      c.clock = () => DateTime(2026, 8, 18, 9);
      final main = await c.instance('main').born(by: tester, title: 'main');
      expect(main.here, pt(0));
      expect(main.title, 'main');
      final o = await main.act((a) => writeIn(a, '.place/card.yaml', 'name: X\n'), by: tester, say: 'card');
      expect(o, isA<Landed>());
      final action = (o as Landed).action;
      expect((action.actor, action.say, action.when), (tester, 'card', DateTime(2026, 8, 18, 9)));
      expect(main.here, pt(1));
      expect(main.history().single.point, pt(1));
      final view = await main.read(at: pt(1));
      expect(view.list('.place'), ['card.yaml']);
      expect(String.fromCharCodes(await view.read('.place/card.yaml')), 'name: X\n');
    });
  });

  test('compare-and-swap: an act begun before another landed is refused as moved, nothing lost', () async {
    await runPlace(gate, (fs) async {
      final c = await gate.author(manifestOf('x'), at: Directory('/home/john/x'), plot: Directory('/home/john/x/plot'), actor: tester);
      final i = await c.instance('i').born(by: tester);
      final second = await i.beginAct(by: other);
      writeIn(second, 'b.txt', 'bob');
      expect(await i.act((a) => writeIn(a, 'a.txt', 'a'), by: tester), isA<Landed>());
      final refused = await second.land();
      expect(refused, isA<Moved>());
      expect((refused as Moved).now, pt(1));
      expect(File('${second.directory.path}/b.txt').readAsStringSync(), 'bob');
      expect(i.history().length, 1);
    });
  });

  test('materialize refreshes the view on landing; release removes it; presence is the map', () async {
    await runPlace(gate, (fs) async {
      final c = await gate.author(manifestOf('x'), at: Directory('/home/john/x'), plot: Directory('/home/john/x/plot'), actor: tester);
      final i = await c.instance('i').born(by: tester);
      final view = Directory('/home/john/view');
      await c.materialize(i, at: view);
      expect(c.materializations, {'i': {view}});
      await i.act((a) => writeIn(a, 'f.txt', 'one'), by: tester);
      expect(File('/home/john/view/f.txt').readAsStringSync(), 'one');
      await c.release(view);
      expect(c.materializations['i'], isEmpty);
      expect(view.existsSync(), isFalse);
    });
  });

  test('stand from a remote: light — existence and titles arrive, no content; the address is the first source', () async {
    await runPlace(gate, (fs) async {
      gate.remotes['hub:/t'] = FakeRemote(manifestOf('t'), instances: const [Seed('c1', title: 'AWS cutover')]);
      final c = await gate.stand('hub:/t', at: Directory('/home/john/t'), plot: Directory('/home/john/t-plot')) as FakeCopy;
      expect(c.instances.map((i) => (i.id, i.title, i.here)), [('c1', 'AWS cutover', null)]);
      expect(c.sources.single.address, 'hub:/t');
      expect(c.instance('c1').standingAgainst('hub').relation, Relation.unknown);
    });
  });

  test('pointAsOf and instancesAsOf resolve through the dates landings carry', () async {
    await runPlace(gate, (fs) async {
      final c = await gate.author(manifestOf('x'), at: Directory('/home/john/x'), plot: Directory('/home/john/x/plot'), actor: tester) as FakeCopy;
      var now = DateTime(2026, 8, 1);
      c.clock = () => now;
      final i = await c.instance('i').born(by: tester);
      await i.act((a) => writeIn(a, 'a', '1'), by: tester);
      now = DateTime(2026, 8, 10);
      await i.act((a) => writeIn(a, 'b', '2'), by: tester);
      await c.instance('j').born(by: tester);
      expect(i.pointAsOf(DateTime(2026, 8, 5)), pt(1));
      expect(i.pointAsOf(DateTime(2026, 7, 1)), isNull);
      expect((await i.read(at: pt(1))).list('.'), ['a']);
      expect(c.instancesAsOf(DateTime(2026, 8, 5)).map((x) => x.id), ['i']);
    });
  });
}
