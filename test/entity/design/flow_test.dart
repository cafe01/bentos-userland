import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// §2.6 — flow: arrival preserves the signature, movements are independent
/// per pair, and nothing is ever lost.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('R2.6.4 — a landing on A arrives on B with A\'s actor, date and sentence preserved', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await landed(s1, by: bob, say: 'bob wrote this', title: 'T');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    final report = await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    expect(report, isA<Carried>().having((c) => c.landings, 'landings', greaterThanOrEqualTo(1)));

    final arrived = g.b.instance('s1').history().last;
    expect(arrived.actor, bob);
    expect(arrived.when, act.when);
    expect(arrived.say, 'bob wrote this');
    expect(arrived.title, 'T');
    expect(arrived.point, act.point);
    expect(arrived.arrivedFrom, hub);
    expect(g.b.instance('s1').here, act.point);
  });

  test('R2.6.5 — publish gives, bring-current takes, and a current pair has nothing to carry', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice);
    expect(await g.a.move(s1, source: hub, direction: Direction.publish),
        isA<Carried>().having((c) => c.direction, 'direction', Direction.publish));
    expect(await g.a.move(s1, source: hub, direction: Direction.publish), isA<NothingToCarry>());
    await g.b.contact(hub);
    expect(await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.sync),
        isA<Carried>().having((c) => c.direction, 'direction', Direction.bringCurrent));
    expect(await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.sync), isA<NothingToCarry>());
  });

  test('R2.6.6 — three instances moved with the hub unreachable report three pairs unchanged; a pair against a reachable second source moves', () async {
    final ids = ['s1', 's2', 's3'];
    for (final id in ids) {
      await landed(await g.a.instance(id).born(by: alice), by: alice);
      await g.a.move(g.a.instance(id), source: hub, direction: Direction.publish);
    }
    // A second source: another bare address on the same disk.
    final second = bareHub(g.dir('second'));
    g.a.addSource(Source(name: 'second', address: second, roles: {Role.publishTo, Role.follow}, cadence: const ByHand()));
    await g.a.contact('second');
    final beforeAges = {for (final id in ids) id: g.a.instance(id).standingAgainst(hub).contacted};

    await landed(g.a.instance('s1'), by: alice, path: 'more.txt');
    g.cutHub();

    final reports = <String, MoveReport>{};
    for (final id in ids) {
      reports[id] = await g.a.move(g.a.instance(id), source: hub, direction: Direction.sync);
    }
    for (final id in ids) {
      expect(reports[id], isA<SourceOutOfReach>().having((r) => r.source, 'source', hub), reason: id);
      expectStanding(
        g.a.instance(id).standingAgainst(hub),
        id == 's1' ? Relation.ahead : Relation.current,
        ahead: id == 's1' ? 1 : 0,
        notAfter: beforeAges[id],
        reason: 'the last age stands when the source is out of reach',
      );
    }
    final moved = await g.a.move(g.a.instance('s1'), source: 'second', direction: Direction.publish);
    expect(moved, isA<Carried>());
    expectStanding(g.a.instance('s1').standingAgainst('second'), Relation.current);
  });

  test('R2.6.2 — discovery is contact: an instance the source holds enters B\'s knowledge as existing there', () async {
    await g.b.contact(hub);
    expect(g.b.instances, isEmpty);
    await g.a.instance('new').born(by: alice, title: 'New');
    await g.a.move(g.a.instance('new'), source: hub, direction: Direction.publish);
    final r = await g.b.contact(hub);
    expect(r.discovered, ['new']);
    expect(r.source, hub);
    expect(g.b.instance('new').title, 'New');
    expect(g.b.instance('new').atSources[hub], r.positions['new']);
  });

  test('R2.6.7 — nothing is lost by a movement: the worst outcome is diverged', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, path: 'a0.txt');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);

    final onA = await landed(s1, by: alice, path: 'a1.txt');
    final onB = await landed(g.b.instance('s1'), by: bob, path: 'b1.txt');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    final r = await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.sync);
    expect(r, isA<MovedApart>().having((m) => m.here, 'here', onB.point).having((m) => m.there, 'there', onA.point));
    expect(g.b.instance('s1').here, onB.point, reason: 'B\'s own line was not overwritten');
    expect(g.b.instance('s1').history().map((a) => a.point), contains(onB.point));
    await g.b.instance('s1').read(at: onA.point);
    await g.b.instance('s1').read(at: onB.point);
  });

  test('R2.6.1 — a source unreachable at contact is refused as such and the standing keeps its age', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    final age = s1.standingAgainst(hub).contacted;
    g.cutHub();
    await expectLater(g.a.contact(hub), throwsA(isA<SourceUnreachable>()));
    expectStanding(s1.standingAgainst(hub), Relation.current, notAfter: age);
  });

  test('moveClass — a changed declaration is carried to a copy, which refits', () async {
    // The class line moves by the same verb and is never an instance.
    expect(await g.a.moveClass(source: hub, direction: Direction.publish), isA<NothingToCarry>());
    expect(g.a.instances, isEmpty);

    final revised = Manifest(
      name: thing.name,
      kind: thing.kind,
      instanceName: thing.instanceName,
      rhythm: thing.rhythm,
      functions: const {'hello': 'sh -c "echo hi"'},
    );
    final events = <Event>[];
    final sub = g.a.listen().listen(events.add);
    addTearDown(sub.cancel);
    final o = await declare(g.a, revised, by: alice);
    expect(o, isA<Landed>());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events.single.instance, isNull, reason: 'the class itself landed');
    expect(events.single.point, (o as Landed).action.point);
    expect(g.a.manifest.functions, contains('hello'), reason: 'a class landing is followed by a refit');
    expect(await g.a.moveClass(source: hub, direction: Direction.publish), isA<Carried>());

    expect(g.b.manifest.functions, isNot(contains('hello')));
    expect(await g.b.moveClass(source: hub, direction: Direction.bringCurrent), isA<Carried>());
    expect(g.b.manifest.functions, contains('hello'), reason: 'a bringCurrent that carried is followed by a refit');
    final s1 = await g.b.instance('s1').born(by: bob);
    expect((await s1.run('hello')).out.trim(), 'hi', reason: 'the copy can run the verb it never carried before');
    expect(await g.b.moveClass(source: hub, direction: Direction.bringCurrent), isA<NothingToCarry>());
  });
}
