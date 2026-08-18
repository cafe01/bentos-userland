// Survey — what stands here, read (R6, R7, R9, R13; Places §8.1): things by
// declaration, instances by title, rooms three ways, residents, loose.
import 'dart:io';

import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  group('things', () {
    test('a thing is shown from its declaration and never from its contents (R9)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', kind: 'chat', instances: const [Seed('c1', title: 'AWS cutover'), Seed('c2', title: 'Kickoff')]);
        final view = Survey(place).things.single;
        expect(view.manifest!.kind, 'chat');
        expect(view.undeclared, isNull);
        expect(view.instances.map((i) => i.instance.title), ['AWS cutover', 'Kickoff'], reason: 'the name the thing declares, never the handle');
        expect(view.instances.map((i) => i.instance.id), ['c1', 'c2']);
        expect(copyOf(gate, place, 'aviacao.chat').materializeCalls, isEmpty, reason: 'a survey makes nothing present and reads no content');
      });
    });

    test('an instance is listed because it exists, present or not, and presence is a fact on the view (Places R7)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1'), Seed('c2')]);
        await Presence(place).present('aviacao.chat', 'c1');
        final views = Survey(place).things.single.instances;
        expect(views.map((i) => (i.instance.id, i.present)), [('c1', true), ('c2', false)]);
      });
    });

    test('a held instance carries its pin on the view (R12)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'deck', instances: const [Seed('v2')]);
        await place.arrangement.hold('deck', 'v2', pt(3), actor: tester);
        expect(Survey(place).things.single.instances.single.held!.at, pt(3));
      });
    });

    test('a thing recorded and not stood is shown, with no manifest and no instances', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, 'hub:/places/hq', '/home/john/hq', name: 'hq',
            arrangement: record(things: [('far.chat', 'hub:/things/far.chat')]));
        final view = Survey(place).things.single;
        expect(view.entry.name, 'far.chat');
        expect(view.manifest, isNull);
        expect(view.instances, isEmpty);
      });
    });

    test('a thing that declares nothing legible is shown as unknown, never hidden (Places R5)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'blob');
        copyOf(gate, place, 'blob').manifestRefusal = 'not a declaration';
        final view = Survey(place).things.single;
        expect(view.entry.name, 'blob');
        expect(view.manifest, isNull);
        expect(view.undeclared, contains('not a declaration'), reason: 'the refusal\'s own words');
      });
    });

    test('the survey is offline: no contact, no manifest read at an address', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1')]);
        final before = (gate.manifestAtCalls.length, copyOf(gate, place, 'aviacao.chat').contactCalls.length);
        Survey(place).desk;
        expect((gate.manifestAtCalls.length, copyOf(gate, place, 'aviacao.chat').contactCalls.length), before);
      });
    });
  });

  group('rooms', () {
    test('recorded and standing, recorded and not, and marked but unrecorded — all three, none hidden (R6)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await genesis('/home/john/hq/aviacao');
        await place.arrangement.addRoom('far', standFrom: 'hub:/places/far', actor: tester);
        // A line of another place stood inside this tree: marked, recorded nowhere here.
        final elsewhere = await genesis('/home/john/other');
        await elsewhere.stand(await elsewhere.fork('alt', actor: tester), at: dir('/home/john/hq/stray'));
        final rooms = Survey(place).rooms;
        expect(rooms.whereType<StandingRoom>().single.entry.name, 'aviacao');
        expect(rooms.whereType<StandingRoom>().single.place.root.path, '/home/john/hq/aviacao');
        expect(rooms.whereType<RecordedRoom>().single.entry.name, 'far');
        expect(rooms.whereType<UnrecordedRoom>().single.at.path, '/home/john/hq/stray');
      });
    });
  });

  group('residents and loose', () {
    test('residents by name and declared kind, never interpreted (R8)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await place.arrangement.reside('ada', kind: 'being', actor: tester);
        await place.arrangement.reside('mariela', kind: 'whatever-she-says', actor: tester);
        expect(Survey(place).residents.map((r) => (r.name, r.kind)), [('ada', 'being'), ('mariela', 'whatever-she-says')]);
      });
    });

    test('loose is what remains: not .place, not an anchor, not a room; names only, contents never read (R7)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1')]);
        await Presence(place).present('aviacao.chat', 'c1');
        await genesis('/home/john/hq/aviacao');
        File('/home/john/hq/photo.jpg').writeAsStringSync('not read');
        Directory('/home/john/hq/misc').createSync();
        final loose = Survey(place).loose.map((e) => e.path).toSet();
        expect(loose, {'/home/john/hq/photo.jpg', '/home/john/hq/misc'});
      });
    });

    test('a directory at an instance\'s address that the copy does not report is loose, not a presence', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1')]);
        Directory('/home/john/hq/aviacao.chat/c1').createSync(recursive: true);
        expect(Survey(place).things.single.instances.single.present, isFalse);
        expect(Survey(place).loose, isEmpty, reason: 'the anchor is recorded: what is under it is not the place\'s to list either');
      });
    });
  });

  test('the desk is one value for one draw, and re-derives on the next (R13)', () async {
    await runPlace(gate, (fs) async {
      final place = await genesis('/home/john/hq', name: 'HQ');
      final one = Survey(place).desk;
      expect(one.card.name, 'HQ');
      expect(one.line.name, 'main');
      expect(one.things, isEmpty);
      await installThing(gate, place, 'a.chat');
      expect(one.things, isEmpty, reason: 'a value');
      expect(Survey(place).desk.things.map((t) => t.entry.name), ['a.chat']);
    });
  });
}
