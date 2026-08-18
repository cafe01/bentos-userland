// Place — genesis (R1, R2, R6), the arrangement stood at the root, the plot.
import 'dart:io';

import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:test/test.dart';

import 'design_helpers.dart';
import 'fake_entity.dart';

void main() {
  late FakeGate gate;
  setUp(() => gate = FakeGate());

  group('genesis', () {
    test('marks the directory: it is a place from that moment and not before (R1)', () async {
      await runPlace(gate, (fs) async {
        expect(Place('/home/john/hq').isImplicit, isTrue, reason: 'unmarked resolves to the implicit home');
        await genesis('/home/john/hq', name: 'HQ');
        final place = Place('/home/john/hq/deep/inside');
        expect(place.isImplicit, isFalse);
        expect(place.root.path, '/home/john/hq', reason: 'handle resolves to the enclosing marked root');
      });
    });

    test('authors the arrangement copy at the root, with its slice of the plot', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final own = ownCopy(gate, place);
        expect(own.directory.path, place.root.path, reason: 'the arrangement is stood at the root: it *is* the tree');
        expect(own.manifest.kind, 'place', reason: 'one class of kind .place');
        expect(own.plot.path, place.plot('place').path, reason: 'its private slice is the place tenant\'s ground');
      });
    });

    test('births the first line and lands the card as the first action, signed', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq', name: 'HQ', owner: 'John');
        final own = ownCopy(gate, place);
        expect(own.bornCalls.map((c) => c.$1), ['main']);
        expect(own.actCalls.single.$2, tester, reason: 'every write carries the stated actor');
        expect(place.card.name, 'HQ');
        expect(place.card.owner, 'John');
        expect(place.line.name, 'main');
        expect(place.lines.map((l) => l.name), ['main']);
      });
    });

    test('the card is read from the arrangement tree at the root, live', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq', name: 'HQ');
        expect(File('${place.root.path}/.place/card.yaml').existsSync(), isTrue, reason: 'the card is tracked declaration');
        // A landing by another copy arriving would refresh the view; the fake does the same.
        await landRecord(gate, place, card: 'name: Renamed\n');
        expect(place.card.name, 'Renamed', reason: 'handles are live: the next read sees the landed card');
      });
    });

    test('inside a marked place, genesis records the room in the parent (R6)', () async {
      await runPlace(gate, (fs) async {
        final parent = await genesis('/home/john/ws');
        await genesis('/home/john/ws/aviacao');
        expect(parent.arrangement.rooms.map((r) => r.name), ['aviacao']);
        expect(ownCopy(gate, parent).actCalls.last.$2, tester, reason: 'the second landing is signed by the same actor');
      });
    });

    test('inside the implicit home, no parent landing is attempted', () async {
      await runPlace(gate, (fs) async {
        await genesis('/home/john/hq');
        expect(gate.copyAt('/home/john'), isNull, reason: 'implicit places hold no arrangement');
      });
    });

    test('an implicit place refuses every writing member with a value, never a throw', () async {
      await runPlace(gate, (fs) async {
        final home = Place('/home/john');
        expect(home.arrangement.things, isEmpty);
        final outcome = await home.arrangement.reside('ada', kind: 'being', actor: tester);
        expect(outcome, isA<NotAPlace<Resident>>());
      });
    });

    test('genesis writes the ignore rule: the plot is residue, the two record files are declaration', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final rule = File('${place.root.path}/.gitignore').readAsStringSync();
        expect(rule, contains('.place/*'));
        expect(rule, contains('!.place/card.yaml'));
        expect(rule, contains('!.place/arrangement.yaml'));
      });
    });
  });

  group('plot', () {
    test('one plot per place, from any line (R1.3)', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        final line = await place.fork('contratos-first', actor: tester);
        final stood = await place.stand(line);
        expect(stood.root.path, isNot(place.root.path));
        expect(stood.plot('mem').path, place.plot('mem').path, reason: 'the plot is anchored to the arrangement copy, not to the root the handle was minted at');
      });
    });

    test('a thing\'s slice is under the entity namespace, keyed by name', () async {
      await runPlace(gate, (fs) async {
        final place = await genesis('/home/john/hq');
        await installThing(gate, place, 'aviacao.chat');
        final call = gate.standCalls.single;
        expect(call.$3.path, '${place.plot('entity').path}/aviacao.chat');
      });
    });
  });
}
