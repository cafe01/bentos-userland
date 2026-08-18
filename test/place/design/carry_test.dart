// Place — carry and materialize (R33, R34, R34.1): a place stood from an
// address, light; its things and rooms stood light afterwards; the place's
// own standing against its own sources, with an age.
import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart' hide Landed, Gated;
import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  final hq = 'hub:/places/hq';

  group('carry (R33)', () {
    test('stands the arrangement copy light at the directory and makes the default line present there', () async {
      await runPlace(gate, (fs) async {
        gate.remotes[hq] = FakeRemote(manifestOf('hq', kind: 'place'), instances: const [Seed('main', title: 'main')]);
        final place = await Place.carry(hq, at: dir('/home/john/hq'));
        expect(place.root.path, '/home/john/hq');
        expect(place.isImplicit, isFalse, reason: 'a carried place is marked');
        final stand = gate.standCalls.single;
        expect(stand.$1, hq);
        expect(stand.$2.path, '/home/john/hq');
        expect(stand.$3.path, place.plot('place').path);
        final own = ownCopy(gate, place);
        expect(own.materializeCalls.single.$1, 'main');
        expect(own.materializeCalls.single.$2.path, '/home/john/hq');
        expect(place.line.name, 'main');
      });
    });

    test('is usable as soon as the record can be read; nothing of any thing\'s mass moved', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq',
            arrangement: record(things: [('aviacao.chat', 'hub:/things/aviacao.chat'), ('notes.mem', 'hub:/things/notes.mem')]));
        expect(place.card.name, 'hq');
        expect(place.arrangement.things.map((t) => t.name), ['aviacao.chat', 'notes.mem']);
        expect(gate.standCalls.length, 1, reason: 'only the arrangement copy was stood');
        expect(place.arrangement.copyOf('aviacao.chat'), isNull, reason: 'recorded, not stood');
      });
    });

    test('the arrangement copy arrives with the address as its first source, and the place records its own standing against it (R34)', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq');
        expect(place.arrangement.sources.map((s) => s.address), [hq]);
        final own = ownCopy(gate, place);
        own.standings['hub'] = {'main': Standing.known(relation: Relation.behind, behind: 2, ahead: 0, contacted: DateTime(2026, 8, 18, 9))};
        final st = place.arrangement.standing.single;
        expect(st.line.name, 'main');
        expect(st.source.name, 'hub');
        expectStanding(st.standing, Relation.behind, behind: 2, reason: 'R34.1: a carried place whose record moved upstream says so');
      });
    });

    test('a place created here has no source yet and says so; carried places have one', () async {
      await runPlace(gate, (fs) async {
        final made = await genesis('/home/john/made');
        expect(made.arrangement.sources, isEmpty);
        expect(made.arrangement.standing, isEmpty, reason: 'no source, no standing line — not unknown, none');
        final carried = await carryRoom(gate, hq, '/home/john/hq', name: 'hq');
        expect(carried.arrangement.sources, hasLength(1));
      });
    });

    test('a place created with a source records it on the arrangement copy and nowhere in the record', () async {
      await runPlace(gate, (fs) async {
        final src = Source(name: 'hub', address: 'hub:/places/made', roles: const {Role.publishTo, Role.follow}, cadence: const ByHand());
        final made = await genesis('/home/john/made', source: src);
        expect(ownCopy(gate, made).sources.map((s) => s.address), ['hub:/places/made']);
        expect(File('${made.root.path}/.place/arrangement.yaml').readAsStringSync(), isNot(contains('hub:/places/made')));
      });
    });

    test('the place\'s own movement is per source, and an unreachable source stops nothing (R34, R31)', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq');
        final own = ownCopy(gate, place);
        own.sources.add(const Source(name: 'mirror', address: 'mirror:/hq', roles: {Role.follow}, cadence: ByHand()));
        own.unreachable.add('hub');
        final reports = await place.arrangement.move(Direction.sync);
        expect(reports.map((r) => r.source), ['hub', 'mirror']);
        expect(reports[0], isA<SourceOutOfReach>());
        expect(reports[1], isA<NothingToCarry>());
        expect(own.moveCalls.map((c) => (c.$1, c.$2)), [('main', 'hub'), ('main', 'mirror')]);
      });
    });

    test('an unreachable address stands nothing and says so', () async {
      await runPlace(gate, (fs) async {
        gate.remotes[hq] = FakeRemote(manifestOf('hq', kind: 'place'), reachable: false);
        await expectLater(Place.carry(hq, at: dir('/home/john/hq')), throwsA(isA<SourceUnreachable>()));
        expect(Place('/home/john/hq').isImplicit, isTrue, reason: 'nothing was marked');
      });
    });
  });

  group('materialize (R33)', () {
    test('stands every recorded thing light at its anchor with its slice of the plot, and reports per entry', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq',
            arrangement: record(things: [('aviacao.chat', 'hub:/things/aviacao.chat'), ('notes.mem', 'hub:/things/notes.mem')]));
        gate.remotes['hub:/things/aviacao.chat'] = FakeRemote(manifestOf('aviacao.chat', kind: 'chat'), instances: const [Seed('c1', title: 'AWS cutover')]);
        gate.remotes['hub:/things/notes.mem'] = FakeRemote(manifestOf('notes.mem', kind: 'mem'));
        final report = await place.arrangement.materialize();
        expect(report.map((s) => (s.name, s.stood)), [('aviacao.chat', true), ('notes.mem', true)]);
        expect(gate.standCalls.skip(1).map((c) => c.$2.path), ['/home/john/hq/aviacao.chat', '/home/john/hq/notes.mem']);
        expect(gate.standCalls.skip(1).map((c) => c.$3.path), ['${place.plot('entity').path}/aviacao.chat', '${place.plot('entity').path}/notes.mem']);
        expect(place.arrangement.copyOf('aviacao.chat'), isNotNull);
        expect(copyOf(gate, place, 'aviacao.chat').materializeCalls, isEmpty, reason: 'light: no instance made present');
        expect(copyOf(gate, place, 'aviacao.chat').instances.map((i) => i.title), ['AWS cutover'], reason: 'existence and titles arrived without content (entity R2.1.5)');
      });
    });

    test('one entry that cannot be stood stops nothing else, and the report says why', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq',
            arrangement: record(things: [('gone.chat', 'hub:/things/gone.chat'), ('notes.mem', 'hub:/things/notes.mem')]));
        gate.remotes['hub:/things/notes.mem'] = FakeRemote(manifestOf('notes.mem'));
        final report = await place.arrangement.materialize();
        expect(report[0].stood, isFalse);
        expect(report[0].reason, isNotNull);
        expect(report[1].stood, isTrue);
      });
    });

    test('is idempotent: what already stands is not stood again', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq',
            arrangement: record(things: [('notes.mem', 'hub:/things/notes.mem')]));
        gate.remotes['hub:/things/notes.mem'] = FakeRemote(manifestOf('notes.mem'));
        await place.arrangement.materialize();
        await place.arrangement.materialize();
        expect(gate.standCalls.length, 2, reason: 'the arrangement, then the thing, once');
      });
    });

    test('carries every recorded room that has an address, at roomOf, and rooms without one are reported', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, hq, '/home/john/hq', name: 'hq',
            arrangement: record(rooms: [('aviacao', 'hub:/places/aviacao'), ('local-only', null)]));
        gate.remotes['hub:/places/aviacao'] = FakeRemote(manifestOf('aviacao', kind: 'place'), instances: const [Seed('main', title: 'main')]);
        final report = await place.arrangement.materialize();
        expect(report.firstWhere((s) => s.name == 'aviacao').stood, isTrue);
        expect(report.firstWhere((s) => s.name == 'local-only').stood, isFalse);
        expect(Place('/home/john/hq/aviacao').isImplicit, isFalse);
        expect(Place('/home/john/hq/aviacao').root.path, place.arrangement.roomOf('aviacao').path);
        expect(Place('/home/john/hq/aviacao').parent!.root.path, place.root.path);
      });
    });
  });
}
