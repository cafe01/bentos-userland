import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'ground.dart';

/// §2.4 — one landing, one event; arming is the copy's; delivery once, in
/// order, never replayed, never blocking.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  /// A command that appends one line to [log] each time it runs. The count of
  /// lines is the count of deliveries.
  String tally(File log) => 'sh -c "echo . >> ${log.path}"';

  Future<int> lines(File log) async {
    // Give a hook process the moment it needs to exit.
    for (var i = 0; i < 20 && !log.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return log.existsSync() ? log.readAsLinesSync().length : 0;
  }

  test('R2.4.3 — an armed command wakes exactly once per landing, and not for landings before the arming', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, path: 'm/0.txt');
    final log = File(p.join(g.dir('log').path, 'a.log'));
    final reg = g.a.arm(tally(log), instance: 's1');
    expect(g.a.armed.map((r) => r.id), contains(reg.id));

    await landed(s1, by: alice, path: 'm/1.txt');
    await landed(s1, by: alice, path: 'm/2.txt');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await lines(log), 2, reason: 'the landing before the arming is not replayed');
  });

  test('R2.4.3 — events for one instance arrive in the order the landings occurred', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final seen = <Point>[];
    final sub = g.a.listen(instance: 's1').listen((e) => seen.add(e.point));
    addTearDown(sub.cancel);
    final points = <Point>[];
    for (var i = 0; i < 3; i++) {
      points.add((await landed(s1, by: alice, path: 'm/$i.txt')).point);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(seen, points);
  });

  test('R2.4.1 — the event says which entity, instance, actor, when, and the sentence; never content', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final events = <Event>[];
    final sub = g.a.listen().listen(events.add);
    addTearDown(sub.cancel);
    final act = await landed(s1, by: bob, say: 'hi', content: 'SECRET');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final e = events.single;
    expect(e.entity, thing.name);
    expect(e.instance, 's1');
    expect(e.point, act.point);
    expect(e.actor, bob);
    expect(e.when, act.when);
    expect(e.say, 'hi');
    expect(e.arrivedFrom, isNull);
  });

  test('R2.6.4 + R2.4.1 — a landing on A arrives on B, wakes B\'s armed command once, and is marked as arrived', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    final log = File(p.join(g.dir('log').path, 'b.log'));
    g.b.arm(tally(log), instance: 's1');
    final events = <Event>[];
    final sub = g.b.listen(instance: 's1').listen(events.add);
    addTearDown(sub.cancel);

    final act = await landed(s1, by: alice, say: 'from A');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await lines(log), 1);
    final e = events.single;
    expect(e.arrivedFrom, hub);
    expect(e.actor, alice, reason: 'never re-signed by the receiving copy');
    expect(e.when, act.when);
    expect(e.say, 'from A');
  });

  test('R2.4.2 — an arming stands on this copy only and does not travel', () async {
    g.a.arm('sh -c true');
    expect(g.b.armed, isEmpty);
    final c = await Copy.stand(g.hubAddress, at: g.dir('c/copy'), plot: g.dir('c/plot'));
    expect(c.armed, isEmpty);
  });

  test('R2.4.3 — a command that fails never prevents the landing nor blocks another command', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final log = File(p.join(g.dir('log').path, 'ok.log'));
    g.a.arm('sh -c "exit 7"');
    g.a.arm('/nonexistent/command');
    g.a.arm(tally(log));
    final o = await land(s1, by: alice);
    expect(o, isA<Landed>());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await lines(log), 1);
  });

  test('R2.4.3 — armOnce fires once and is gone; disarm removes an arming', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final log = File(p.join(g.dir('log').path, 'once.log'));
    final once = g.a.armOnce(tally(log));
    expect(once.once, isTrue);
    await landed(s1, by: alice, path: 'm/1.txt');
    await landed(s1, by: alice, path: 'm/2.txt');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await lines(log), 1);
    expect(g.a.armed.map((r) => r.id), isNot(contains(once.id)));

    final log2 = File(p.join(g.dir('log').path, 'disarm.log'));
    final reg = g.a.arm(tally(log2));
    g.a.disarm(reg.id);
    await landed(s1, by: alice, path: 'm/3.txt');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await lines(log2), 0);
  });
}
