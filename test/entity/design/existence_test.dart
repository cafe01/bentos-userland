import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:test/test.dart';

import 'ground.dart';

/// §2.1 — existence, positions and mass. Existence arrives light; content
/// arrives on first read; a light copy is not a degraded one.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('R2.1.2 — an instance born on A exists on B without content after one contact', () async {
    final s1 = await g.a.instance('s1').born(by: alice, title: 'first');
    await landed(s1, by: alice, content: 'x' * 4096);
    await g.a.move(s1, source: hub, direction: Direction.publish);

    expect(g.b.instances.map((i) => i.id), isNot(contains('s1')),
        reason: 'B has not contacted the hub since s1 was born');
    final report = await g.b.contact(hub);
    expect(report.discovered, contains('s1'));
    expect(report.positions, contains('s1'));

    final far = g.b.instance('s1');
    expect(g.b.instances.map((i) => i.id), contains('s1'));
    expect(far.here, isNull, reason: 'known to exist, no landing held here');
    expect(far.atSources[hub], isNotNull);
  });

  test('R2.1.3 — the far instance reads on B after one more contact, at the point A published', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await landed(s1, by: alice, content: 'the content');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);

    final far = g.b.instance('s1');
    final view = await far.read(at: act.point);
    expect(String.fromCharCodes(await view.read('messages/1.txt')), 'the content');
    expect(far.here, isNull, reason: 'a read never moves the instance (R2.3.1)');
  });

  test('R2.1.3 — a read with no reachable source is refused and names the sources tried', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await landed(s1, by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    g.cutHub();
    await expectLater(
      g.b.instance('s1').read(at: act.point),
      throwsA(isA<ContentUnavailable>()
          .having((e) => e.tried, 'tried', contains(hub))
          .having((e) => e.instance, 'instance', 's1')),
    );
  });

  test('R2.1.2 — standing a copy against a hub with a large instance transfers no instance content', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final big = List.filled(1 << 20, 'a').join();
    await landed(s1, by: alice, path: 'big.txt', content: big);
    await g.a.move(s1, source: hub, direction: Direction.publish);

    final c = await Copy.stand(g.hubAddress,
        at: g.dir('c/copy'), plot: g.dir('c/plot'));
    expect(c.instances.map((i) => i.id), contains('s1'));
    final bytes = c.directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .fold<int>(0, (n, f) => n + f.lengthSync());
    expect(bytes, lessThan(1 << 19),
        reason: 'existence and positions arrive; a megabyte of content must not');
  });

  test('R2.1.5 — a far instance is titled on B with no content held, and the fallback is never the handle', () async {
    final s1 = await g.a.instance('s1').born(by: alice, title: 'Plans');
    await landed(s1, by: alice, title: 'Plans, revised');
    final s2 = await g.a.instance('s2').born(by: alice);
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.a.move(s2, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    g.cutHub();

    expect(g.b.instance('s1').title, 'Plans, revised',
        reason: 'the newest landing that carries a title wins');
    expect(g.b.instance('s2').title, thing.instanceName.fallback);
    expect(g.b.instance('s2').title, isNot('s2'));
  });

  test('R2.1.6 — birth is legible on every copy that knows the instance, forever', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await landed(s1, by: alice);
    final s2 = await g.a.instance('s2').born(by: bob, from: act.point);
    for (final i in [s1, s2]) {
      await g.a.move(i, source: hub, direction: Direction.publish);
    }
    await g.b.contact(hub);
    g.cutHub();

    expect(g.b.instance('s1').birth, isA<FromGenesis>().having((b) => b.by, 'by', alice));
    expect(
      g.b.instance('s2').birth,
      isA<ForkedFrom>()
          .having((b) => b.by, 'by', bob)
          .having((b) => b.instance, 'instance', 's1')
          .having((b) => b.at, 'at', act.point),
    );
  });

  test('R2.1.4 — dropping every source loses nothing that was here', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await landed(s1, by: alice, content: 'kept');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    await g.b.instance('s1').read(at: act.point);

    g.b.dropSource(hub);
    g.cutHub();
    expect(g.b.sources, isEmpty);
    expect(g.b.instances.map((i) => i.id), contains('s1'));
    final view = await g.b.instance('s1').read(at: act.point);
    expect(String.fromCharCodes(await view.read('messages/1.txt')), 'kept');
  });

  test('R2.5.3 — a declared field the primitive does not know is carried unread, never refused', () async {
    final later = Manifest(
      name: 'later.chat',
      kind: 'chat',
      instanceName: thing.instanceName,
      rhythm: thing.rhythm,
      fields: const {'from-a-later-platform': true},
    );
    final g2 = await Ground.stand(manifest: later);
    expect(g2.b.manifest.fields['from-a-later-platform'], isTrue);
    expect((await Copy.manifestAt(g2.hubAddress)).name, 'later.chat');
  });

  test('R2.5.3 — Copy.at on a directory that holds no copy is refused as such', () {
    expect(() => Copy.at(g.dir('nothing'), plot: g.dir('nothing-plot')),
        throwsA(isA<NotACopy>()));
  });

  test('R2.6.1 — a changed rhythm is this copy\'s own and does not travel', () async {
    g.a.changeSource(hub, cadence: const OnClock(Duration(minutes: 5)));
    expect(g.a.sources.single.cadence, isA<OnClock>());
    final c = await Copy.stand(g.hubAddress,
        at: g.dir('c/copy'), plot: g.dir('c/plot'));
    expect(c.sources.single.cadence, isA<ByHand>(),
        reason: 'a fresh copy arrives with the manifest\'s defaults');
    expect(c.sources.single.roles, thing.rhythm.roles);
  });
}
