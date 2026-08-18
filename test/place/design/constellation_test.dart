// Constellation — standing and movement at the place's scale (R12.1, R12.2,
// R29–R32): per instance per source, offline, every line with its age; held
// folded in; movement per pair with one failure stopping nothing.
import 'package:bentos_userland/src/entity/contract/contract.dart' hide Landed, Gated;
import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  final t0 = DateTime(2026, 8, 18, 9);

  Future<(Place, FakeCopy)> ground() async {
    final place = await genesis('/home/john/hq');
    await installThing(gate, place, 'aviacao.chat', instances: const [Seed('c1'), Seed('c2')]);
    final copy = copyOf(gate, place, 'aviacao.chat');
    copy.sources.add(const Source(name: 'mirror', address: 'mirror:/aviacao.chat', roles: {Role.follow}, cadence: ByHand()));
    copy.standings['hub'] = {
      'c1': Standing.known(relation: Relation.behind, behind: 2, ahead: 0, contacted: t0),
      'c2': Standing.known(relation: Relation.current, behind: 0, ahead: 0, contacted: t0),
    };
    copy.standings['mirror'] = {'c1': Standing.known(relation: Relation.ahead, behind: 0, ahead: 1, contacted: t0)};
    return (place, copy);
  }

  group('standing (R29, R30)', () {
    test('one line per instance per source, each the entity\'s answer with its age; the scope is stated', () async {
      await runPlace(gate, (fs) async {
        final (place, copy) = await ground();
        final lines = Constellation(place).standing(const OneThing('aviacao.chat'));
        expect(lines.map((l) => (l.instance, l.source.name)), [('c1', 'hub'), ('c1', 'mirror'), ('c2', 'hub'), ('c2', 'mirror')]);
        expectStanding(lines[0].standing, Relation.behind, behind: 2);
        expectStanding(lines[1].standing, Relation.ahead, ahead: 1);
        expectStanding(lines[2].standing, Relation.current);
        expectStanding(lines[3].standing, Relation.unknown, reason: 'never contacted about c2: unknown, and undated');
        expect(copy.standingCalls.length, 4, reason: 'asked of the copy at the moment of the question, per pair');
        expect(copy.contactCalls, isEmpty, reason: 'offline');
      });
    });

    test('OneInstance and ThisPlace scopes; the place is one more thing under ThisPlace (R34)', () async {
      await runPlace(gate, (fs) async {
        final (place, _) = await ground();
        final own = ownCopy(gate, place);
        own.sources.add(const Source(name: 'hub', address: 'hub:/hq', roles: {Role.publishTo}, cadence: ByHand()));
        own.standings['hub'] = {'main': Standing.known(relation: Relation.ahead, behind: 0, ahead: 3, contacted: t0)};
        final one = Constellation(place).standing(const OneInstance('aviacao.chat', 'c2'));
        expect(one.map((l) => (l.instance, l.source.name)), [('c2', 'hub'), ('c2', 'mirror')]);
        final all = Constellation(place).standing(const ThisPlace());
        expect(all.where((l) => l.thing == arrangementThing).single.instance, 'main');
        expectStanding(all.where((l) => l.thing == arrangementThing).single.standing, Relation.ahead, ahead: 3);
        expect(all.length, 5);
      });
    });

    test('a held instance reads held with the distance the source has moved past the pin, never behind alone (R12.1)', () async {
      await runPlace(gate, (fs) async {
        final (place, copy) = await ground();
        await place.arrangement.hold('aviacao.chat', 'c1', pt(1), actor: tester);
        copy.pastPoint['hub'] = {'c1': {pt(1): 3}};
        copy.contacted['hub'] = t0;
        final line = Constellation(place).standing(const OneInstance('aviacao.chat', 'c1')).firstWhere((l) => l.source.name == 'hub');
        expect(line.held, isNotNull);
        expect(line.held!.pin.at, pt(1));
        expect(line.held!.pastPin, 3, reason: 'the entity\'s count from the pin (R2.9.1b), not from this copy\'s tip');
        expect(line.standing.contacted, isNotNull, reason: 'held still carries the age');
        expect(copy.standingCalls.where((c) => c.$1 == 'c1' && c.$2 == 'hub').single.$3, pt(1), reason: 'asked from the pin');
      });
    });

    test('a thing recorded and not stood yields no standing lines and no error', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, 'hub:/places/hq', '/home/john/hq', name: 'hq',
            arrangement: record(things: [('far.chat', 'hub:/things/far.chat')]));
        expect(Constellation(place).standing(const OneThing('far.chat')), isEmpty);
      });
    });

    test('PlaceAndRooms descends into rooms that stand, labelling each line by room', () async {
      await runPlace(gate, (fs) async {
        final (place, _) = await ground();
        final room = await genesis('/home/john/hq/aviacao');
        await installThing(gate, room, 'notes.mem', address: 'hub:/notes', instances: const [Seed('n1')]);
        copyOf(gate, room, 'notes.mem').standings['hub'] = {'n1': Standing.known(relation: Relation.current, behind: 0, ahead: 0, contacted: t0)};
        final lines = Constellation(place).standing(const PlaceAndRooms());
        expect(lines.where((l) => l.room == null).map((l) => l.thing).toSet(), {'aviacao.chat', arrangementThing});
        expect(lines.where((l) => l.room == 'aviacao').map((l) => l.thing).toSet(), {'notes.mem', arrangementThing});
        expect(Constellation(place).standing(const ThisPlace()).where((l) => l.room != null), isEmpty, reason: 'ThisPlace never descends');
      });
    });
  });

  group('move (R31, R32, R12.2)', () {
    test('a movement is a loop of independent pair calls; one unreachable source stops nothing else; the report is per pair', () async {
      await runPlace(gate, (fs) async {
        final (place, copy) = await ground();
        copy.unreachable.add('hub');
        copy.moveAnswers[('c1', 'mirror')] = const Carried(instance: 'c1', source: 'mirror', direction: Direction.bringCurrent, landings: 2);
        final report = await Constellation(place).move(Direction.sync, const OneThing('aviacao.chat'));
        expect(report.direction, Direction.sync);
        expect(report.pairs.map((p) => (p.instance, p.source.name)), [('c1', 'hub'), ('c1', 'mirror'), ('c2', 'hub'), ('c2', 'mirror')]);
        expect((report.pairs[0].movement as Answered).report, isA<SourceOutOfReach>());
        expect((report.pairs[1].movement as Answered).report, isA<Carried>());
        expect((report.pairs[2].movement as Answered).report, isA<SourceOutOfReach>());
        expect((report.pairs[3].movement as Answered).report, isA<NothingToCarry>());
        expect(copy.moveCalls.length, 4, reason: 'every pair was asked, unreachable notwithstanding');
      });
    });

    test('a held instance is reported held and never moved (R12.2)', () async {
      await runPlace(gate, (fs) async {
        final (place, copy) = await ground();
        await place.arrangement.hold('aviacao.chat', 'c1', pt(1), actor: tester);
        final report = await Constellation(place).move(Direction.bringCurrent, const OneThing('aviacao.chat'));
        expect(report.pairs.where((p) => p.instance == 'c1').map((p) => p.movement), everyElement(isA<HeldPair>()));
        expect(copy.moveCalls.map((c) => c.$1).toSet(), {'c2'});
        expect(place.arrangement.pin('aviacao.chat', 'c1'), isNotNull, reason: 'never silently unpinned');
      });
    });

    test('diverged crosses as MovedApart, unmerged, and nothing decides which copy is true (R32)', () async {
      await runPlace(gate, (fs) async {
        final (place, copy) = await ground();
        copy.moveAnswers[('c1', 'hub')] = MovedApart(instance: 'c1', source: 'hub', here: pt(2), there: pt(2));
        final report = await Constellation(place).move(Direction.sync, const OneInstance('aviacao.chat', 'c1'));
        expect((report.pairs.first.movement as Answered).report, isA<MovedApart>());
        expect(copy.actCalls, isEmpty, reason: 'no reconciliation was landed on anyone\'s behalf');
        expect(copy.moveCalls.length, 2, reason: 'and the second pair was still moved');
      });
    });

    test('a thing recorded and not stood is NotStood, and stops nothing', () async {
      await runPlace(gate, (fs) async {
        final place = await carryRoom(gate, 'hub:/places/hq', '/home/john/hq', name: 'hq',
            arrangement: record(things: [('far.chat', 'hub:/things/far.chat')]));
        final report = await Constellation(place).move(Direction.sync, const ThisPlace());
        expect(report.pairs.where((p) => p.thing == 'far.chat').single.movement, isA<NotStood>());
        expect(report.pairs.where((p) => p.thing == arrangementThing), hasLength(1), reason: 'the place itself moved against its source');
      });
    });

    test('ThisPlace moves the arrangement\'s own lines too (R34), and PlaceAndRooms descends', () async {
      await runPlace(gate, (fs) async {
        final (place, _) = await ground();
        final own = ownCopy(gate, place);
        own.sources.add(const Source(name: 'hub', address: 'hub:/hq', roles: {Role.publishTo}, cadence: ByHand()));
        final room = await genesis('/home/john/hq/aviacao');
        await installThing(gate, room, 'notes.mem', address: 'hub:/notes', instances: const [Seed('n1')]);
        final report = await Constellation(place).move(Direction.publish, const PlaceAndRooms());
        expect(own.moveCalls.map((c) => c.$1), ['main']);
        expect(copyOf(gate, room, 'notes.mem').moveCalls.map((c) => c.$1), ['n1']);
        expect(report.pairs.where((p) => p.room == 'aviacao').map((p) => p.thing).toSet(), {'notes.mem', arrangementThing});
      });
    });
  });
}
