// Arrangement — the record and its acts (R5, R8, R11, R12, R14, R21, R28).
import 'dart:io';

import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  group('install', () {
    test('reads the declaration first, stands the copy light at its anchor, lands the entry with the stand-from address (R5, R11)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final addr = 'hub:/things/aviacao.chat';
        final entry = await installThing(gate, place, 'aviacao.chat', address: addr);
        expect(gate.manifestAtCalls, [addr], reason: 'the name is known before anything is stood');
        final stand = gate.standCalls.single;
        expect(stand.$1, addr);
        expect(stand.$2.path, place.arrangement.anchorOf('aviacao.chat').path);
        expect(stand.$2.path, '${place.root.path}/aviacao.chat', reason: 'the anchor is the thing\'s name under the root');
        expect(entry.standFrom, addr);
        expect(place.arrangement.things.map((t) => t.name), ['aviacao.chat']);
        expect(ownCopy(gate, place).actCalls.last.$2, tester);
      });
    });

    test('the copy arrives with the rhythm its manifest declares and the place records none of it (R10, R11)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final record = File('${place.root.path}/.place/arrangement.yaml').readAsStringSync();
        expect(record, isNot(contains('hub')), reason: 'no source, role or cadence is written in the record');
        expect(record, contains('hub:/things/aviacao.chat'), reason: 'only the stand-from address');
      });
    });

    test('a name already recorded here is refused before anything is stood (R21)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final again = 'elsewhere:/aviacao.chat';
        gate.remotes[again] = FakeRemote(manifestOf('aviacao.chat'));
        final outcome = await place.arrangement.install(again, actor: tester);
        expect(outcome, isA<Duplicate<ThingEntry>>());
        expect(gate.standCalls.length, 1, reason: 'nothing was stood for the refused install');
      });
    });

    test('an unreachable address is refused with nothing recorded', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final addr = 'hub:/things/far.chat';
        gate.remotes[addr] = FakeRemote(manifestOf('far.chat'), reachable: false);
        final outcome = await place.arrangement.install(addr, actor: tester);
        expect(outcome, isA<Unreachable<ThingEntry>>());
        expect(place.arrangement.things, isEmpty);
      });
    });

    test('a copy stood whose landing was refused is not torn down, and the outcome says so', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final addr = 'hub:/things/aviacao.chat';
        gate.remotes[addr] = FakeRemote(manifestOf('aviacao.chat'));
        ownCopy(gate, place).gateWords = 'the room is sealed';
        final outcome = await place.arrangement.install(addr, actor: tester);
        expect(outcome, isA<Gated<ThingEntry>>());
        expect((outcome as Gated).words, 'the room is sealed');
        expect(gate.copyAt('${place.root.path}/aviacao.chat'), isNotNull, reason: 'standing is not destruction');
      });
    });

    test('the ignore rule is regenerated from the record: anchors and rooms never read as the place\'s own content', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        await genesis('/home/john/hq/contratos');
        final rule = File('${place.root.path}/.gitignore').readAsStringSync();
        expect(rule.split('\n'), containsAll(['/aviacao.chat/', '/contratos/']));
      });
    });
  });

  group('acts', () {
    test('every act is one signed landing on the line\'s instance', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final own = ownCopy(gate, place);
        final before = own.actCalls.length;
        await place.arrangement.reside('ada', kind: 'being', actor: tester);
        await place.arrangement.reside('mariela', kind: 'person', actor: other);
        await place.arrangement.leave('ada', actor: tester);
        expect(own.actCalls.length, before + 3);
        expect(own.actCalls.map((c) => c.$1).toSet(), {'main'});
        expect(own.actCalls.sublist(before).map((c) => c.$2), [tester, other, tester]);
        expect(place.arrangement.residents.map((r) => (r.name, r.kind)), [('mariela', 'person')]);
      });
    });

    test('a landing that moved under the act is re-read and retried, bounded; the third refusal is Contested', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final own = ownCopy(gate, place);
        own.moveUnderNext = 2;
        final ok = await place.arrangement.reside('ada', kind: 'being', actor: tester);
        expect(ok, isA<Landed<Resident>>());
        own.moveUnderNext = 3;
        final refused = await place.arrangement.reside('bob', kind: 'being', actor: tester);
        expect(refused, isA<Contested<Resident>>());
      });
    });

    test('diverged and gated cross unflattened and are never retried', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final own = ownCopy(gate, place);
        own.diverge = true;
        final before = own.actCalls.length;
        expect(await place.arrangement.reside('ada', kind: 'being', actor: tester), isA<Diverged<Resident>>());
        expect(own.actCalls.length, before + 1);
        own.diverge = false;
        own.gateWords = 'no';
        expect(await place.arrangement.reside('ada', kind: 'being', actor: tester), isA<Gated<Resident>>());
        expect(own.actCalls.length, before + 2);
      });
    });

    test('hold writes a pin and nothing else; unhold removes it (R12)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'deck', instances: [Seed('v2', title: 'v2')]);
        final copy = copyOf(gate, place, 'deck');
        final at = pt(3);
        final held = await place.arrangement.hold('deck', 'v2', at, actor: tester);
        expect(held, isA<Landed<Pin>>());
        expect(place.arrangement.pin('deck', 'v2')!.at, at);
        expect(copy.materializeCalls, isEmpty, reason: 'a pin makes nothing present');
        expect(copy.moveCalls, isEmpty, reason: 'and moves nothing');
        await place.arrangement.unhold('deck', 'v2', actor: tester);
        expect(place.arrangement.pin('deck', 'v2'), isNull);
      });
    });

    test('the stand-from address changes only by saying so (R5)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final moved = 'newhub:/aviacao.chat';
        await place.arrangement.restandFrom('aviacao.chat', moved, actor: tester);
        expect(place.arrangement.thing('aviacao.chat')!.standFrom, moved);
      });
    });

    test('remove keeps the copy (R28)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final anchor = place.arrangement.anchorOf('aviacao.chat').path;
        expect(await place.arrangement.remove('aviacao.chat', actor: tester), isA<Landed<void>>());
        expect(place.arrangement.things, isEmpty);
        expect(gate.copyAt(anchor), isNotNull);
        expect(place.arrangement.copyOf('aviacao.chat'), isNull, reason: 'not recorded here any more');
      });
    });
  });

  group('the record', () {
    test('records lineage at genesis: the parent\'s name, and its address when it has one', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws', name: 'workspace');
        final room = await genesis('/home/john/ws/aviacao');
        expect(room.arrangement.above!.name, 'workspace');
        expect(room.arrangement.above!.standFrom, isNull, reason: 'the parent has no source yet');
        expect(ws.arrangement.above, isNull, reason: 'the home is implicit and is nobody\'s lineage');
      });
    });

    test('is a value: two reads of the same line are equal and mutating nothing', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'a.chat');
        final one = place.arrangement;
        final two = place.arrangement;
        expect(one.things.map((t) => t.name), two.things.map((t) => t.name));
        expect(one.line.name, two.line.name);
      });
    });

    test('a record from a newer schema is refused legibly, never misread', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await landRecord(gate, place, arrangement: 'schema: 99\nthings: []\n');
        expect(() => place.arrangement.things, throwsA(isA<UnreadableRecord>()));
      });
    });
  });
}
