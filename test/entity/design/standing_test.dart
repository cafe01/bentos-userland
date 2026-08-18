import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// §2.9 — standing is read from a record, never measured. Every question here
/// is answered with the network cut, and every answer carries its age.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('R2.9.1/R2.9.2 — with the network cut, every instance answers a relation, its counts and an age', () async {
    for (final id in ['s1', 's2']) {
      await landed(await g.a.instance(id).born(by: alice), by: alice);
      await g.a.move(g.a.instance(id), source: hub, direction: Direction.publish);
    }
    await landed(g.a.instance('s2'), by: alice, path: 'more.txt');
    await g.b.contact(hub);
    final t = DateTime.now();
    g.cutHub();

    expectStanding(g.a.instance('s1').standingAgainst(hub), Relation.current, notAfter: t);
    expectStanding(g.a.instance('s2').standingAgainst(hub), Relation.ahead, ahead: 1, notAfter: t);
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.behind, behind: 1, notAfter: t,
        reason: 'B knows the hub holds one landing it lacks');
    for (final copy in [g.a, g.b]) {
      for (final i in copy.instances) {
        final all = i.standing;
        expect(all.keys, contains(hub));
        expectStanding(all[hub]!, all[hub]!.relation, behind: all[hub]!.behind, ahead: all[hub]!.ahead);
      }
    }
  });

  test('R2.9.2 — a source never contacted answers unknown with no age', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final second = bareHub(g.dir('second'));
    g.a.addSource(Source(name: 'second', address: second, roles: {Role.follow}, cadence: const ByHand()));
    expectStanding(s1.standingAgainst('second'), Relation.unknown);
    expectStanding(s1.standing['second']!, Relation.unknown);
    expectStanding(s1.standingAgainst('never-added'), Relation.unknown);
  });

  test('R2.9.4 — a landing on the hub moves this copy\'s answer only after a contact, never before', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    final age = g.b.instance('s1').standingAgainst(hub).contacted;

    await landed(s1, by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.current, notAfter: age,
        reason: 'the record has not been refreshed; the answer is as of the last contact');
    await g.b.contact(hub, about: g.b.instance('s1'));
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.behind, behind: 1, notBefore: age);
  });

  test('R2.9.2 — a copy that has held no contact for a while answers with that age and not a fresher one', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    final age = s1.standingAgainst(hub).contacted!;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    g.cutHub();
    expectStanding(s1.standingAgainst(hub), Relation.current, notAfter: age);
    expect(s1.standingAgainst(hub).contacted, age);
  });

  test('R2.9.1b — standing from a named point: the distance the source moved past it', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final pin = (await landed(s1, by: alice, path: 'p0.txt')).point;
    await landed(s1, by: alice, path: 'p1.txt');
    await landed(s1, by: alice, path: 'p2.txt');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    g.cutHub();

    // The holder of a pin asks from the pin; the primitive knows nothing of why.
    expectStanding(g.b.instance('s1').standingAgainst(hub, from: pin), Relation.behind, behind: 2);
    expectStanding(s1.standingAgainst(hub, from: pin), Relation.behind, behind: 2);
    expectStanding(s1.standingAgainst(hub), Relation.current);
    expect(s1.landingsBetween(from: pin, to: s1.here!), 2);
    expect(s1.landingsBetween(from: s1.here!, to: pin), isNull);
  });

  test('R2.9.3 — standing is answered per pair, for every source a copy holds', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice);
    final second = bareHub(g.dir('second'));
    g.a.addSource(Source(name: 'second', address: second, roles: {Role.publishTo}, cadence: const ByHand()));
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.a.contact('second');
    g.cutHub();
    final all = s1.standing;
    expect(all.keys, unorderedEquals([hub, 'second']));
    expectStanding(all[hub]!, Relation.current);
    expectStanding(all['second']!, Relation.ahead, ahead: 1);
  });
}
