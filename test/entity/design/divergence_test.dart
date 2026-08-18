import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// §2.7 — divergence: surfaced, held on both sides, never merged; and the
/// thing that declares divergence its own.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  /// A and B both hold s1 at [base]; then each lands once from it. Returns
  /// the two landings.
  Future<(Action onA, Action onB)> fork() async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, path: 'base.txt');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    final onA = await landed(s1, by: alice, path: 'a.txt', content: 'A');
    final onB = await landed(g.b.instance('s1'), by: bob, path: 'b.txt', content: 'B');
    return (onA, onB);
  }

  test('§2.7 — A and B land from the same point, both learn diverged, both hold both lines', () async {
    final (onA, onB) = await fork();
    await g.a.move(g.a.instance('s1'), source: hub, direction: Direction.publish);
    expect(await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.sync), isA<MovedApart>());
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.diverged, behind: 1, ahead: 1);
    // B publishes its line where it can — a second address — or A learns of
    // B's line the way the desk does: through the hub once B has published.
    // Here the hub carries A's line; B carries both. A learns of B's by
    // contact only after B publishes, and publishing a diverged pair carries
    // nothing — so A's view stays *current* until B lands a reconciliation.
    expectStanding(g.a.instance('s1').standingAgainst(hub), Relation.current);

    for (final point in [onA.point, onB.point]) {
      final view = await g.b.instance('s1').read(at: point);
      expect(view.list('.'), anyOf(contains('a.txt'), contains('b.txt')));
    }
    expect(g.b.instance('s1').history().map((a) => a.point), contains(onB.point));
    expect(g.b.instance('s1').here, onB.point, reason: 'nobody picked a winner');
  });

  test('§2.7 — bringing current a diverged instance keeps standing at diverged and overwrites nothing', () async {
    final (_, onB) = await fork();
    await g.a.move(g.a.instance('s1'), source: hub, direction: Direction.publish);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    expect(await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent), isA<MovedApart>());
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.diverged, behind: 1, ahead: 1);
    expect(g.b.instance('s1').here, onB.point);
  });

  test('R2.7.3 — a reconciliation landed on B stands ahead on B and behind on A until contact', () async {
    final (onA, onB) = await fork();
    await g.a.move(g.a.instance('s1'), source: hub, direction: Direction.publish);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.sync);

    // The reconciliation is an ordinary action on B, carrying bob's signature.
    final r = await landed(g.b.instance('s1'), by: bob, path: 'both.txt', content: 'A+B', say: 'reconciled');
    expect(r.actor, bob);
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.ahead, ahead: 2,
        reason: 'no longer diverged against the hub once the reconciliation contains its line');
    expect(await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.publish), isA<Carried>());
    expectStanding(g.b.instance('s1').standingAgainst(hub), Relation.current);

    expectStanding(g.a.instance('s1').standingAgainst(hub), Relation.current,
        reason: 'A has not contacted since; its record still says current');
    await g.a.contact(hub);
    expectStanding(g.a.instance('s1').standingAgainst(hub), Relation.behind, behind: 2);
    expect(g.a.instance('s1').here, onA.point, reason: 'a contact moves nothing');
    await g.a.move(g.a.instance('s1'), source: hub, direction: Direction.bringCurrent);
    expect(g.a.instance('s1').here, r.point);
    expect(g.a.instance('s1').history().map((a) => a.point), containsAll([onA.point, onB.point, r.point]));
  });

  group('R2.7.4 — a thing that declares divergence its own', () {
    const ruleActor = Actor(name: 'merge-rule', address: 'rule@suite.chat');
    Manifest owning(String run) => Manifest(
          name: 'owning.chat',
          kind: 'chat',
          instanceName: thing.instanceName,
          rhythm: thing.rhythm,
          reconciliation: ReconciliationRule(actor: ruleActor, run: run),
        );

    test('never reports diverged: the rule lands an ordinary action signed as the rule, and both landings stay', () async {
      // The rule is a command the host runs on the receiving copy; what it
      // leaves standing is landed. A rule that does nothing lands the
      // receiving line as the reconciliation.
      final gg = await Ground.stand(manifest: owning('sh -c true'));
        final s1 = await gg.a.instance('s1').born(by: alice);
      await landed(s1, by: alice, path: 'base.txt');
      await gg.a.move(s1, source: hub, direction: Direction.publish);
      await gg.b.contact(hub);
      await gg.b.move(gg.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
      final onA = await landed(s1, by: alice, path: 'a.txt');
      final onB = await landed(gg.b.instance('s1'), by: bob, path: 'b.txt');
      await gg.a.move(s1, source: hub, direction: Direction.publish);

      final report = await gg.b.move(gg.b.instance('s1'), source: hub, direction: Direction.sync);
      expect(report, isNot(isA<MovedApart>()));
      final history = gg.b.instance('s1').history();
      expect(history.map((a) => a.point), containsAll([onA.point, onB.point]));
      expect(history.last.actor, ruleActor);
      expectStanding(gg.b.instance('s1').standingAgainst(hub), Relation.ahead, ahead: 2,
          reason: "B's own landing plus the rule's; the reconciliation contains A's line");
    });

    test('falls back to diverged, with nothing lost, when the rule refuses', () async {
      final gg = await Ground.stand(manifest: owning('sh -c "exit 1"'));
        final s1 = await gg.a.instance('s1').born(by: alice);
      await landed(s1, by: alice, path: 'base.txt');
      await gg.a.move(s1, source: hub, direction: Direction.publish);
      await gg.b.contact(hub);
      await gg.b.move(gg.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
      final onA = await landed(s1, by: alice, path: 'a.txt');
      final onB = await landed(gg.b.instance('s1'), by: bob, path: 'b.txt');
      await gg.a.move(s1, source: hub, direction: Direction.publish);

      expect(await gg.b.move(gg.b.instance('s1'), source: hub, direction: Direction.sync), isA<MovedApart>());
      expectStanding(gg.b.instance('s1').standingAgainst(hub), Relation.diverged, behind: 1, ahead: 1);
      expect(gg.b.instance('s1').here, onB.point);
      await gg.b.instance('s1').read(at: onA.point);
    });
  });
}
