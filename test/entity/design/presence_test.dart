import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'ground.dart';

/// Presence — a materialization is a view: two may stand at once, the copy
/// keeps its own views true, a pinned one never moves, release destroys nothing.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  String at(Directory d, String path) => File(p.join(d.path, path)).readAsStringSync();

  test('the same instance stands at two directories at once, both readable', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, content: 'v1');
    final one = await g.a.materialize(s1, at: g.dir('view/one'));
    final two = await g.a.materialize(s1, at: g.dir('view/two'));
    expect(one.pinned, isFalse);
    expect(at(one.directory, 'messages/1.txt'), 'v1');
    expect(at(two.directory, 'messages/1.txt'), 'v1');
    expect(g.a.materializations['s1'], hasLength(2));
  });

  test('a landing advances every unpinned view of the instance; a pinned one does not move', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final v1 = await landed(s1, by: alice, content: 'v1');
    final live = await g.a.materialize(s1, at: g.dir('view/live'));
    final pinned = await g.a.materialize(s1, at: g.dir('view/pinned'), point: v1.point);
    expect(pinned.pinned, isTrue);
    expect(pinned.point, v1.point);

    await landed(s1, by: alice, content: 'v2');
    expect(at(live.directory, 'messages/1.txt'), 'v2');
    expect(at(pinned.directory, 'messages/1.txt'), 'v1');
  });

  test('an arrival advances the copy\'s own views like a local landing', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, content: 'v1');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.contact(hub);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    final view = await g.b.materialize(g.b.instance('s1'), at: g.dir('view/b'));
    expect(at(view.directory, 'messages/1.txt'), 'v1');

    await landed(s1, by: alice, content: 'v2');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    await g.b.move(g.b.instance('s1'), source: hub, direction: Direction.bringCurrent);
    expect(at(view.directory, 'messages/1.txt'), 'v2');
  });

  test('a view is never the writing surface: writing in it lands nothing', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, content: 'v1');
    final view = await g.a.materialize(s1, at: g.dir('view/one'));
    File(p.join(view.directory.path, 'messages/1.txt')).writeAsStringSync('scribble');
    expect(s1.history().length, 1);
    final read = await s1.read(at: s1.here!);
    expect(String.fromCharCodes(await read.read('messages/1.txt')), 'v1');
  });

  test('releasing either leaves the other whole; releasing both leaves history and standing untouched', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    await landed(s1, by: alice, content: 'v1');
    await g.a.move(s1, source: hub, direction: Direction.publish);
    final one = await g.a.materialize(s1, at: g.dir('view/one'));
    final two = await g.a.materialize(s1, at: g.dir('view/two'));
    final before = s1.standingAgainst(hub);

    await g.a.release(one.directory);
    expect(at(two.directory, 'messages/1.txt'), 'v1');
    expect(g.a.materializations['s1'], hasLength(1));
    await g.a.release(two.directory);
    expect(g.a.materializations['s1'] ?? const <Directory>{}, isEmpty);
    expect(s1.history().length, 1);
    expect(s1.here, isNotNull);
    expectStanding(s1.standingAgainst(hub), before.relation, behind: before.behind, ahead: before.ahead);
    expect(s1.standingAgainst(hub), before);
  });
}
