import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// R2.2.2, R2.2.3, R2.1.6 — reads at a point move nothing; *as of* answers as
/// the world stood, by the date each landing carries.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('R2.2.2 — any point of the history reads as files without presence and without moving the point', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final p1 = await landed(s1, by: alice, content: 'one');
    final p2 = await landed(s1, by: alice, content: 'two');
    final v1 = await s1.read(at: p1.point);
    expect(String.fromCharCodes(await v1.read('messages/1.txt')), 'one');
    expect(s1.here, p2.point);
    expect(g.a.materializations['s1'] ?? const {}, isEmpty, reason: 'a read is not a materialization');
  });

  test('R2.2.3 — pointAsOf resolves through the dates the landings carry', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final p1 = await landed(s1, by: alice, content: 'one');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final between = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final p2 = await landed(s1, by: alice, content: 'two');

    expect(s1.pointAsOf(between), p1.point);
    expect(s1.pointAsOf(DateTime.now()), p2.point);
    expect(s1.pointAsOf(s1.birth.when.subtract(const Duration(days: 1))), isNull);
  });

  test('R2.2.3 — as of answers as the world stood: B\'s answer changes honestly after an older landing arrives', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, content: 'one');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);

    // A lands at t1; B does not learn of it until later. B's answer for an
    // instant after t1 is A's landing's *own* date, never the arrival's.
    final onA = await landed(s1, by: alice, content: 'two');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final afterT1 = DateTime.now();
    final beforeArrival = g.b.instance('s1').pointAsOf(afterT1);
    expect(beforeArrival, isNot(onA.point));

    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    expect(g.b.instance('s1').pointAsOf(afterT1), onA.point,
        reason: 'the landing carries A\'s date, which is before afterT1');
    expect(g.b.instance('s1').history().last.when, onA.when);
  });

  test('R2.1.6 — which instances existed as of an instant follows from their births', () async {
    await g.a.instance('s1').born(by: alice);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final between = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await g.a.instance('s2').born(by: alice);
    expect(g.a.instancesAsOf(between).map((i) => i.id), ['s1']);
    expect(g.a.instancesAsOf(DateTime.now()).map((i) => i.id), unorderedEquals(['s1', 's2']));

    await g.a.move(g.a.instance('s1'), source: hub, direction: Direction.publish);
    await g.a.move(g.a.instance('s2'), source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    g.cutHub();
    expect(g.b.instancesAsOf(between).map((i) => i.id), ['s1'],
        reason: 'answered on B from births, with no content and no network');
  });
}
