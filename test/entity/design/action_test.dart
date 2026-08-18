import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'ground.dart';

/// §2.3 — the action: the private area, the compare-and-swap, the four typed
/// outcomes, the gate.
void main() {
  late Ground g;
  setUp(() async => g = await Ground.stand());
  tearDown(disposeGrounds);

  test('R2.3.1 — writing in a private area changes nothing a reader sees until it lands', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final before = s1.here;
    final act = await s1.beginAct(by: alice);
    write(act, 'messages/1.txt', 'draft');
    expect(s1.here, before);
    expect(s1.history(), isEmpty);
    expect(p.isWithin(g.a.plot.path, act.directory.path), isTrue,
        reason: 'the private area lives in the plot slice, never in the copy');
    final outcome = await act.land(say: 'said');
    expect(outcome, isA<Landed>());
    expect(s1.here, isNot(before));
    expect(s1.history().single.say, 'said');
  });

  test('R2.3.4/R2.3.5 — two actors contend; the second is refused as moved with nothing lost', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final first = await s1.beginAct(by: alice);
    final second = await s1.beginAct(by: bob);
    write(first, 'a.txt', 'alice');
    write(second, 'b.txt', 'bob');
    final o1 = await first.land();
    final o2 = await second.land();
    expect(o1, isA<Landed>());
    expect(
      o2,
      isA<Moved>()
          .having((m) => m.from, 'from', second.from)
          .having((m) => m.now, 'now', (o1 as Landed).action.point),
    );
    expect(File(p.join(second.directory.path, 'b.txt')).readAsStringSync(), 'bob',
        reason: 'the loser\'s private area still holds every byte it wrote');
    expect(s1.history().length, 1);
  });

  test('R2.3.4 — retrying is the actor\'s decision: the primitive never retries a Moved', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final second = await s1.beginAct(by: bob);
    await landed(s1, by: alice);
    write(second, 'b.txt', 'bob');
    expect(await second.land(), isA<Moved>());
    expect(s1.history().length, 1, reason: 'nothing landed on bob\'s behalf');
    // The actor retries as-is: a fresh act, same content.
    final again = await s1.beginAct(by: bob);
    write(again, 'b.txt', 'bob');
    expect(await again.land(), isA<Landed>());
    expect(s1.history().length, 2);
  });

  test('R2.3.2 — a landing is atomic: no reader observes a partial state', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await s1.beginAct(by: alice);
    for (var i = 0; i < 50; i++) {
      write(act, 'f/$i.txt', '$i');
    }
    final o = await act.land();
    final view = await s1.read(at: (o as Landed).action.point);
    expect(view.list('f').length, 50);
    final previous = s1.history();
    expect(previous.length, 1, reason: 'one landing, one record');
  });

  test('R2.3.3 — every landing carries who, when, what it deposited, and the sentence', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final t0 = DateTime.now();
    final act = await landed(s1, by: bob, say: 'wrote a note', title: 'Notes');
    expect(act.actor, bob);
    expect(act.when.isBefore(t0.subtract(const Duration(seconds: 2))), isFalse);
    expect(act.say, 'wrote a note');
    expect(act.title, 'Notes');
    expect(act.arrivedFrom, isNull);
    expect(s1.title, 'Notes');
    final view = await s1.read(at: act.point);
    expect(view.list('messages'), contains('1.txt'));
  });

  test('R2.3.1 — abandon leaves nothing behind and moves nothing', () async {
    final s1 = await g.a.instance('s1').born(by: alice);
    final act = await s1.beginAct(by: alice);
    write(act, 'x.txt', 'x');
    act.abandon();
    expect(act.directory.existsSync(), isFalse);
    expect(s1.here, isNotNull);
    expect(s1.history(), isEmpty);
  });

  group('R2.3.6 — a declared gate', () {
    final gated = Manifest(
      name: 'gated.chat',
      kind: 'chat',
      instanceName: thing.instanceName,
      rhythm: thing.rhythm,
      gates: const [
        GateRule(name: 'no-shouting', run: 'sh -c "echo no shouting allowed; exit 1"'),
      ],
    );

    test('refuses with its own words on A and on B alike', () async {
      final gg = await Ground.stand(manifest: gated);
        for (final copy in [gg.a, gg.b]) {
        final s = await copy.instance('s-${copy.directory.path.hashCode}').born(by: alice);
        final o = await land(s, by: alice, content: 'HELLO');
        expect(
          o,
          isA<Gated>()
              .having((x) => x.rule, 'rule', 'no-shouting')
              .having((x) => x.words, 'words', contains('no shouting allowed')),
          reason: 'on ${copy.directory.path}',
        );
        expect(s.history(), isEmpty, reason: 'gated means not landed');
      }
    });

    test('the same act is refused again', () async {
      final gg = await Ground.stand(manifest: gated);
        final s = await gg.a.instance('s1').born(by: alice);
      final act = await s.beginAct(by: alice);
      write(act, 'a.txt', 'A');
      expect(await act.land(), isA<Gated>());
      expect(await act.land(), isA<Gated>());
    });
  });
}
