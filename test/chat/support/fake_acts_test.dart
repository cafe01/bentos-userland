/// Audits [FakeActs] against [ChatActs.attempt]'s own contract — not against
/// [Channel], since the shape under question is invisible from up there: a
/// contested or barred outcome never surfaces in what a caller reads back,
/// only in whether the gate and the write actually ran to produce it.
///
/// Doubles are witnesses (`discipline/proof/fixture-audit`), and a witness
/// cheaper than the world in exactly the place the world is expensive proves
/// nothing there. These are the tests that make that cost visible.
library;

import 'package:bentos_userland/bentos_chat.dart';
import 'package:test/test.dart';

import 'doubles.dart';

void main() {
  late FakeTree tree;
  late FakeActs acts;

  setUp(() {
    tree = FakeTree();
    acts = FakeActs(tree);
    tree.birth();
  });

  test('a contested attempt still asks the gate and still runs the write',
      () async {
    acts.contestNext('message', 1);
    var gateCalls = 0;
    var writeCalls = 0;
    final outcome = await acts.attempt(
      'message',
      gate: (area) {
        gateCalls++;
        return null;
      },
      write: (area) {
        writeCalls++;
        area.write('messages/x.md', 'body');
      },
    );
    expect(outcome, isA<ChatContested>());
    expect(gateCalls, 1);
    expect(writeCalls, 1);
  });

  test('a barred attempt still asks the gate and still runs the write', () async {
    acts.barNext('message', 'refused by a gate');
    var gateCalls = 0;
    var writeCalls = 0;
    final outcome = await acts.attempt(
      'message',
      gate: (area) {
        gateCalls++;
        return null;
      },
      write: (area) {
        writeCalls++;
        area.write('messages/x.md', 'body');
      },
    );
    expect(outcome, isA<ChatGateRefused>());
    expect(gateCalls, 1);
    expect(writeCalls, 1);
  });

  test('a gate refusal is asked before the write, and the write never runs',
      () async {
    var writeCalls = 0;
    final outcome = await acts.attempt(
      'message',
      gate: (area) => 'no',
      write: (area) => writeCalls++,
    );
    expect(outcome, isA<ChatGateRefused>());
    expect(writeCalls, 0);
  });

  test('every attempt records that the gate was called, contested and '
      'barred alike', () async {
    acts.contestNext('message', 1);
    await acts.attempt('message', gate: (area) => null, write: (area) {});
    acts.barNext('message', 'no');
    await acts.attempt('message', gate: (area) => null, write: (area) {});
    await acts.attempt('message', gate: (area) => null, write: (area) {});

    final attempts = acts.attemptsAt('message');
    expect(attempts, hasLength(3));
    expect(attempts.every((a) => a.gateCalled), isTrue);
  });

  test('the gate reads a fresh area each attempt, so a concurrent change '
      'between attempts is seen', () async {
    tree.land(
      noun: 'membership',
      authorName: 'Alfred',
      authorEmail: 'alfred@bentos.life',
      writes: {'$participantsPath/alfred/joined': '2026-08-06T11:00:00Z\n'},
    );
    acts.contestNext('message', 1);

    final seenAt = <bool>[];
    await acts.attempt(
      'message',
      gate: (area) {
        seenAt.add(area.exists('$participantsPath/alfred'));
        return null;
      },
      write: (area) {},
    );
    // Torn down between the two attempts — the fixture's own hand, standing
    // in for a concurrent leave the real floor would land the same way.
    tree.land(
      noun: 'membership',
      authorName: 'Alfred',
      authorEmail: 'alfred@bentos.life',
      removes: ['$participantsPath/alfred'],
    );
    await acts.attempt(
      'message',
      gate: (area) {
        seenAt.add(area.exists('$participantsPath/alfred'));
        return null;
      },
      write: (area) {},
    );

    expect(seenAt, [true, false]);
  });
}
