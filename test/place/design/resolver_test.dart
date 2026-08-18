// Resolver — a name up the tree, a coordinate to its path (R17, R20–R22).
import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  group('resolve', () {
    test('a thing installed here resolves from here and from every place beneath (R20)', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws');
        await genesis('/home/john/ws/aviacao');
        await installThing(gate, ws, 'rate-table');
        for (final vantage in ['/home/john/ws', '/home/john/ws/aviacao', '/home/john/ws/aviacao/deep']) {
          final r = Resolver.resolve('rate-table', vantage: vantage);
          expect(r, isA<Resolved>(), reason: 'from $vantage');
          expect((r as Resolved).place.root.path, ws.root.path);
          expect(r.anchor.path, ws.arrangement.anchorOf('rate-table').path);
          expect(r.copy, isNotNull);
        }
      });
    });

    test('nearest wins (R21)', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws');
        final room = await genesis('/home/john/ws/aviacao');
        await installThing(gate, ws, 'notes.mem', address: 'hub:/ws-notes');
        await installThing(gate, room, 'notes.mem', address: 'hub:/room-notes');
        final r = Resolver.resolve('notes.mem', vantage: '/home/john/ws/aviacao/x') as Resolved;
        expect(r.place.root.path, room.root.path);
        expect(r.entry.standFrom, 'hub:/room-notes');
      });
    });

    test('resolution is offline and opens no copy until one is found', () async {
      await runPlace(gate, (fs) async {
        await genesis('/home/john/ws');
        await genesis('/home/john/ws/aviacao');
        final before = gate.manifestAtCalls.length;
        expect(Resolver.resolve('nothing', vantage: '/home/john/ws/aviacao'), isA<Unresolved>());
        expect(gate.manifestAtCalls.length, before);
      });
    });

    test('unresolved names every place searched, nearest first', () async {
      await runPlace(gate, (fs) async {
        await genesis('/home/john/ws');
        await genesis('/home/john/ws/aviacao');
        final r = Resolver.resolve('nothing', vantage: '/home/john/ws/aviacao') as Unresolved;
        expect(r.searched.map((p) => p.root.path), ['/home/john/ws/aviacao', '/home/john/ws', '/home/john', '/']);
      });
    });

    test('a carried room whose ancestor is not present says so and names it (R22)', () async {
      await runPlace(gate, (fs) async {
        // The room was born inside `workspace` upstream; here it stands alone under the home.
        final room = await carryRoom(gate, 'hub:/rooms/aviacao', '/home/john/aviacao', name: 'aviacao',
            arrangement: record(above: ('workspace', 'hub:/ws')));
        final r = Resolver.resolve('rate-table', vantage: '/home/john/aviacao');
        expect(r, isA<ThroughAbsentAncestor>());
        final t = r as ThroughAbsentAncestor;
        expect(t.ancestor.name, 'workspace');
        expect(t.ancestor.standFrom, 'hub:/ws');
        expect(t.last.root.path, room.root.path);
      });
    });

    test('a thing recorded and not yet stood resolves with no copy', () async {
      await runPlace(gate, (fs) async {
        await carryRoom(gate, 'hub:/rooms/aviacao', '/home/john/aviacao', name: 'aviacao',
            arrangement: record(things: [('far.chat', 'hub:/far.chat')]));
        final r = Resolver.resolve('far.chat', vantage: '/home/john/aviacao') as Resolved;
        expect(r.copy, isNull);
        expect(r.entry.standFrom, 'hub:/far.chat');
      });
    });

    test('a line is the same place: a vantage inside a stood line resolves the ancestors\' things', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws');
        final hq = await genesis('/home/john/ws/hq');
        await installThing(gate, ws, 'rate-table');
        final alt = await hq.stand(await hq.fork('alt', actor: tester));
        final r = Resolver.resolve('rate-table', vantage: alt.root.path) as Resolved;
        expect(r.place.root.path, ws.root.path);
      });
    });
  });

  group('pathOf', () {
    test('the uniform address, answered whether or not anything stands there (R17)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1', title: 'AWS cutover')]);
        final path = Resolver.pathOf(Coordinate(place: place, thing: 'aviacao.chat', instance: 'c1'));
        expect(path!.path, '${place.root.path}/aviacao.chat/c1', reason: 'the id, never the title');
        expect(Resolver.pathOf(Coordinate(place: place, thing: 'aviacao.chat'))!.path, '${place.root.path}/aviacao.chat');
      });
    });

    test('at another line, the address is under that line\'s root', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
        final line = await place.fork('alt', actor: tester);
        final stood = await place.stand(line);
        final path = Resolver.pathOf(Coordinate(place: place, line: line, thing: 'aviacao.chat', instance: 'c1'));
        expect(path!.path, '${stood.root.path}/aviacao.chat/c1');
      });
    });
  });
}
