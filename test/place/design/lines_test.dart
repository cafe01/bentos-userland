// Place — lines (R23–R28): fork, stand, several at once, as-of, survival.
import 'dart:io';

import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  group('lines', () {
    test('lines are the arrangement copy\'s instances, including one known only at a source', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        ownCopy(gate, place).known['marielas'] = Known('marielas', title: 'marielas', contentHere: false);
        expect(place.lines.map((l) => l.name), ['main', 'marielas']);
      });
    });

    test('fork births a new instance from the line in view and copies the record, never the mass (R24)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final line = await place.fork('contratos-first', actor: tester);
        expect(line.name, 'contratos-first');
        final own = ownCopy(gate, place);
        expect(own.bornCalls.last, ('contratos-first', tester, 'main'));
        expect((await place.at(line)).things.map((t) => t.name), ['aviacao.chat'], reason: 'the arrangement travelled');
        expect(gate.standCalls.length, 1, reason: 'no thing was stood again: a fork costs the record');
      });
    });

    test('fork as of an instant forks from the point the line stood at then', () async {
      await runPlace(gate, (fs) async {
        var now = DateTime(2026, 8, 1);
        final place = await genesis('/home/john/hq');
        final own = ownCopy(gate, place)..clock = () => now;
        await installThing(gate, place, 'a.chat');
        now = DateTime(2026, 8, 10);
        await installThing(gate, place, 'b.chat');
        final line = await place.fork('old', actor: tester, asOf: DateTime(2026, 8, 5));
        expect((await place.at(line)).things.map((t) => t.name), ['a.chat']);
        expect(own.bornCalls.last.$3, 'main');
      });
    });

    test('stand a line: a full place root, same parent, same arrangement copy (R25)', () async {
      await runPlace(gate, (fs) async {
        final ws = await genesis('/home/john/ws');
        final place = await genesis('/home/john/ws/hq');
        final line = await place.fork('alt', actor: tester);
        final stood = await place.stand(line);
        expect(stood.line.name, 'alt');
        expect(stood.root.path, '${place.plot('place').path}/lines/alt', reason: 'default address is under the plot');
        expect(stood.parent!.root.path, ws.root.path, reason: 'a line is the same place seen twice: its parent is the place\'s parent');
        expect(stood.card.name, place.card.name);
        expect(ownCopy(gate, place).materializeCalls.last.$1, 'alt');
      });
    });

    test('stand a line at a directory of one\'s choosing', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final line = await place.fork('alt', actor: tester);
        final stood = await place.stand(line, at: Directory('/home/john/hq-alt'));
        expect(stood.root.path, '/home/john/hq-alt');
        expect(place.stood[line]!.map((d) => d.path), contains('/home/john/hq-alt'));
      });
    });

    test('several lines stand at once, each usable, one walked into by default', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final a = await place.stand(await place.fork('a', actor: tester));
        final b = await place.stand(await place.fork('b', actor: tester));
        expect(place.stood.keys.map((l) => l.name).toSet(), {'main', 'a', 'b'});
        await installThing(gate, a, 'only-on-a.chat');
        expect(a.arrangement.things.map((t) => t.name), ['only-on-a.chat']);
        expect(b.arrangement.things, isEmpty, reason: 'what differs between lines is which things stand');
        expect(place.arrangement.things, isEmpty);
      });
    });

    test('the arrangement as of an instant is the record as the world stood (R27)', () async {
      await runPlace(gate, (fs) async {
        var now = DateTime(2026, 7, 20);
        final place = await genesis('/home/john/hq');
        ownCopy(gate, place).clock = () => now;
        await installThing(gate, place, 'old.sheet');
        now = DateTime(2026, 8, 1);
        await place.arrangement.remove('old.sheet', actor: tester);
        await installThing(gate, place, 'new.sheet');
        final then = await place.asOf(DateTime(2026, 7, 25));
        expect(then.asOf, DateTime(2026, 7, 25));
        expect(then.things.map((t) => t.name), ['old.sheet']);
        expect(place.arrangement.things.map((t) => t.name), ['new.sheet']);
      });
    });

    test('a removed thing keeps its copy in the plot and is reachable at a line that still refers to it (R28)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'gone.chat');
        final kept = await place.fork('kept', actor: tester);
        await place.arrangement.remove('gone.chat', actor: tester);
        expect(gate.copyAt(place.arrangement.anchorOf('gone.chat').path), isNotNull, reason: 'removal is not destruction');
        expect((await place.at(kept)).things.map((t) => t.name), ['gone.chat']);
        expect((await place.at(kept)).copyOf('gone.chat'), isNotNull);
      });
    });
  });
}
