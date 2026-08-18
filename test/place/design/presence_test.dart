// Presence — the uniform address, make present, release (R15–R19).
import 'dart:io';

import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  test('installing makes nothing present (R15)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
      expect(copyOf(gate, place, 'aviacao.chat').materializeCalls, isEmpty);
      expect(Presence(place).isPresent('aviacao.chat', 'c1'), isFalse);
    });
  });

  test('present asks the copy to materialize at the uniform address, at the tip (R16, R19)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
      final made = await Presence(place).present('aviacao.chat', 'c1');
      expect(made, isA<Present>());
      final call = copyOf(gate, place, 'aviacao.chat').materializeCalls.single;
      expect(call.$2.path, '${place.root.path}/aviacao.chat/c1');
      expect(call.$3, isNull, reason: 'not held: the tip');
      expect((made as Present).at.path, call.$2.path);
    });
  });

  test('a held instance is stood at its pin (R12)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'deck', instances: [Seed('v2')]);
      await place.arrangement.hold('deck', 'v2', pt(3), actor: tester);
      await Presence(place).present('deck', 'v2');
      expect(copyOf(gate, place, 'deck').materializeCalls.single.$3, pt(3));
    });
  });

  test('presence is read from the copy\'s materializations and never from a stat (R13)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1'), Seed('c2')]);
      Directory('${place.root.path}/aviacao.chat/c2').createSync(recursive: true);
      final presence = Presence(place);
      expect(presence.isPresent('aviacao.chat', 'c2'), isFalse, reason: 'a directory the copy does not report is not a presence');
      await presence.present('aviacao.chat', 'c1');
      expect(presence.isPresent('aviacao.chat', 'c1'), isTrue);
      expect(presence.presences, {'aviacao.chat': {'c1'}});
    });
  });

  test('the same instance stands present in two lines at once, one copy seen twice (R18)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
      final alt = await place.stand(await place.fork('alt', actor: tester));
      await Presence(place).present('aviacao.chat', 'c1');
      await Presence(alt).present('aviacao.chat', 'c1');
      final copy = copyOf(gate, place, 'aviacao.chat');
      expect(copyOf(gate, alt, 'aviacao.chat'), same(copy), reason: 'one copy per place');
      expect(copy.materializeCalls.map((c) => c.$2.path), ['${place.root.path}/aviacao.chat/c1', '${alt.root.path}/aviacao.chat/c1']);
      expect(Presence(place).isPresent('aviacao.chat', 'c1'), isTrue);
      expect(Presence(alt).isPresent('aviacao.chat', 'c1'), isTrue);
    });
  });

  test('present is idempotent where already present', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
      await Presence(place).present('aviacao.chat', 'c1');
      await Presence(place).present('aviacao.chat', 'c1');
      expect(copyOf(gate, place, 'aviacao.chat').materializeCalls.length, 1);
    });
  });

  test('content at no reachable source refuses with the sources tried, and nothing is retried (Places R22)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('far')]);
      copyOf(gate, place, 'aviacao.chat').unfetchable.add('far');
      final made = await Presence(place).present('aviacao.chat', 'far');
      expect(made, isA<Unfetchable>());
      expect((made as Unfetchable).tried, ['hub:/things/aviacao.chat']);
      expect(Presence(place).isPresent('aviacao.chat', 'far'), isFalse);
    });
  });

  test('a thing recorded and not stood answers NotStanding', () async {
    await runPlace(gate, (fs) async {
      final room = await carryRoom(gate, 'hub:/rooms/r', '/home/john/r', name: 'r',
          arrangement: record(things: [('far.chat', 'hub:/far.chat')]));
      expect(await Presence(room).present('far.chat', 'x'), isA<NotStanding>());
    });
  });

  test('release removes the view and destroys nothing', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq');
      await installThing(gate, place, 'aviacao.chat', instances: [Seed('c1')]);
      final presence = Presence(place);
      await presence.present('aviacao.chat', 'c1');
      await presence.release('aviacao.chat', 'c1');
      expect(presence.isPresent('aviacao.chat', 'c1'), isFalse);
      expect(copyOf(gate, place, 'aviacao.chat').releaseCalls.single.path, '${place.root.path}/aviacao.chat/c1');
      expect(copyOf(gate, place, 'aviacao.chat').instances.map((i) => i.id), contains('c1'), reason: 'the instance still exists');
    });
  });
}
