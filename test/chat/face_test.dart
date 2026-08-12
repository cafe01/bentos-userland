/// The gate over the shell face — what a verb *prints* and what it *exits with*.
///
/// Disjoint from `contract_suite.dart` on purpose: that one judges the channel,
/// this one judges the face over it, and the two share no claim. Everything
/// asserted here is a fact about the terminal — a line, a stream, a number —
/// which is why the floor is a seam rather than a real installation: a gate that
/// had to install an entity to find out that a bad `--since` exits 64 would be
/// judging the primitive and calling it the face.
///
/// The claims that are *not* here are the ones the material gate owns: that the
/// bodies exist, that git signs, that an act lands.
library;

import 'dart:async';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/chat_client.dart' show Ticker;
import 'package:bentos_userland/entity.dart' show EntityNotInstalled;
import 'package:test/test.dart';

import 'support/doubles.dart';

/// The floor, doubled: one tree, one set of bodies, and a place that answers for
/// whichever channels a fixture says are installed under it.
final class FakeFloor implements ChatFloor {
  FakeFloor({this.here = const ['fabrica']});

  final tree = FakeTree();
  late final FakeActs actsDouble = FakeActs(tree)..identity = identityDouble;
  final identityDouble = FakeIdentity();

  /// `check` alone still runs through [ChatBodies] — it carries no seat and
  /// is not a [Channel] method.
  late final FakeBodies bodyDouble = FakeBodies(tree);

  /// What the place carries — **the ambient walk's third step**, and the only
  /// way a fixture can make that step answer, decline, or hesitate.
  List<String> here;

  /// Every `place` the face resolved from, so a claim about `-C` is checkable
  /// rather than assumed.
  final List<String> vantages = [];

  /// Makes the place answer the way the real primitive does when there is no
  /// installation above the vantage: by throwing. The double throws **the
  /// floor's own type**, since a fake exception of ours would prove that the
  /// face catches a class this test invented.
  bool throwsNotInstalled = false;

  /// The names the face asked for, in order.
  final List<String> opened = [];

  /// Makes the floor refuse to say who is speaking, the way the real one does
  /// for a being of the kind that has stated no identity.
  ///
  /// A double that can only answer is a double that hides an arm the real
  /// floor has: identity resolution *refuses*, and a gate over a face that
  /// never sees the refusal proves only the happy half.
  bool refusesIdentity = false;

  @override
  Identity get identity {
    if (refusesIdentity) {
      throw const NoIdentity(
        'a being of the kind states its own identity — set '
        r'$BENTOS_CHAT_IDENTITY ("Name <email>" or a bare email)',
      );
    }
    return identityDouble;
  }

  @override
  Channel channel(
    String name, {
    required String place,
    String? cursor,
    Identity? identity,
  }) {
    opened.add(name);
    vantages.add(place);
    // The real floor resolves identity here too, so the refusal must reach a
    // caller that never asked for [identity] by name.
    identity ?? this.identity;
    actsDouble.channel = name;
    return channelConstruction(
      name: name,
      acts: actsDouble,
      tree: tree,
      identity: identityDouble,
      ticker: () => ticker,
      cursor: cursor,
      // Fixed, so the printed lines this gate judges do not move with the
      // wall clock — the same instant the retired shell's doubles hard-coded.
      clock: () => DateTime.utc(2026, 8, 6, 12),
    );
  }

  @override
  ChatBodies bodies(String name, {required String place, Identity? identity}) {
    vantages.add(place);
    return bodyDouble;
  }

  @override
  List<String> channels(String place) {
    vantages.add(place);
    if (throwsNotInstalled) throw EntityNotInstalled(chatOntology, place);
    return here;
  }

  /// What [dispatchTicker] hands back — a [_NoopTicker] until a fixture
  /// swaps in a [FakeTicker] it can drive by hand, since most verbs judged
  /// here never touch the doorbell at all.
  Ticker ticker = _NoopTicker();

  @override
  Ticker dispatchTicker(String place) {
    vantages.add(place);
    return ticker;
  }
}

/// No verb of this gate drives a ticker — it judges the face's printed lines
/// and exit codes, never a live view — so the double is a stub with nothing
/// behind it.
final class _NoopTicker implements Ticker {
  @override
  Stream<void> get ticks => const Stream.empty();

  @override
  void nudge() {}

  @override
  void dispose() {}

  @override
  bool get connected => true;
}

/// One invocation of the coreutil, captured whole.
final class Run {
  Run(this.exitCode, this.out, this.err);

  final int exitCode;
  final String out;
  final String err;

  /// stdout as lines, with the trailing newline's empty tail dropped — a face
  /// that prints records is judged by records.
  List<String> get lines =>
      out.isEmpty ? const [] : out.trimRight().split('\n');
}

void main() {
  late FakeFloor floor;

  setUp(() => floor = FakeFloor());

  Future<Run> run(
    List<String> args, {
    Map<String, String> env = const {},
    String cwd = '/campus',
    String stdin = '',
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final face = ChatRunner(
      out: out,
      err: err,
      currentDirectory: cwd,
      environment: env,
      readStdin: () async => stdin,
      floor: floor,
    );
    await face.run(args);
    return Run(face.exitCode, out.toString(), err.toString());
  }

  /// Seats the caller, so the gate under every writing body is satisfied and a
  /// claim about `say` is about `say`.
  Future<void> seated() => run(['join']);

  group('the exit table', () {
    test('an act that lands exits 0 and prints its commit', () async {
      final result = await run(['join']);

      expect(result.exitCode, 0);
      expect(result.lines.single, 'c100000');
      expect(result.err, isEmpty);
    });

    test('a refusal exits 3, in the floor\'s own words on stderr', () async {
      // Born (someone else's channel), but nobody joined under this identity:
      // the membership gate is the one gate this application has, and it must
      // not be confused with the channel's own birth.
      floor.tree.birth();
      final result = await run(['say', 'hello']);

      expect(result.exitCode, 3);
      expect(result.out, isEmpty);
      expect(result.err, contains('is not in bentos.chat:fabrica'));
    });

    test('a lost race exits 75 and is NOT flattened into a refusal', () async {
      // The distinction is the whole point: nobody decided anything, and a busy
      // channel must not read as a hostile one at the exact boundary where a
      // script reads it.
      await seated();
      floor.actsDouble.contestNext('message', defaultAttempts);

      final result = await run(['say', 'hello']);

      expect(result.exitCode, 75);
      expect(result.exitCode, isNot(3));
      expect(result.err, contains('try again'));
    });

    test('an unknown verb exits 64', () async {
      final result = await run(['yell', 'hello']);

      expect(result.exitCode, 64);
      expect(result.err, contains('yell'));
    });
  });

  group('the face names the program the caller invoked', () {
    // Found by reading a real terminal: every line said `chat:` while the
    // command on the PATH is `bentos.chat` — and `chat` is the *other*
    // coreutil, which makes the report actively misleading rather than merely
    // loose. One prefix, and it is the entity's own name, because one string
    // serves identity, repository and PATH entry.
    for (final (what, args, env) in <(String, List<String>, Map<String, String>)>[
      ('a coordinate of another ontology', ['-c', 'bentos.llm:x', 'where'], {}),
      ('an empty coordinate', ['-c', '', 'where'], {}),
      ('no channel anywhere', ['where'], {'BENTOS_CHAT_NOTHING': ''}),
      ('a refusal with no words', ['say', 'hello'], {}),
    ]) {
      test('$what is reported under bentos.chat', () async {
        if (what == 'no channel anywhere') floor.here = const [];
        if (what == 'a refusal with no words') {
          floor.tree.birth();
          floor.actsDouble.barNext('message', '');
        }

        final result = await run(args, env: env);

        expect(result.err, startsWith('bentos.chat: '));
        // Not merely *starts with the right thing*: the old prefix must be
        // gone, and `chat: ` is a substring of nothing here by accident.
        expect(result.err, isNot(contains(RegExp(r'(^|\s)chat: '))));
      });
    }

    test('a stumble too, since it is the line a busy channel prints most',
        () async {
      await seated();
      floor.actsDouble.contestNext('message', defaultAttempts);

      final result = await run(['say', 'hello']);

      expect(result.err, startsWith('bentos.chat: '));
    });
  });

  group('the ambient coordinate', () {
    test('the argument wins, and says so', () async {
      final result = await run(
        ['-c', 'bentos.chat:outra', 'where'],
        env: {'BENTOS_CHAT_CHANNEL': 'bentos.chat:fabrica'},
      );

      expect(result.lines.single, 'bentos.chat:outra\t-c');
    });

    test('the variable answers when nobody typed one', () async {
      final result = await run(
        ['where'],
        env: {'BENTOS_CHAT_CHANNEL': 'bentos.chat:fabrica'},
      );

      expect(result.lines.single, 'bentos.chat:fabrica\tBENTOS_CHAT_CHANNEL');
    });

    test('the place answers last, and only when it carries exactly one',
        () async {
      final result = await run(['where']);

      expect(result.lines.single, 'bentos.chat:fabrica\tthe place');
    });

    test('a bare name is a channel of this ontology', () async {
      final result = await run(['-c', 'fabrica', 'where']);

      expect(result.lines.single, 'bentos.chat:fabrica\t-c');
    });

    test('several channels is a question for the caller — 64, listed', () async {
      floor.here = ['fabrica', 'lab'];

      final result = await run(['where']);

      // The ambiguity is information: guessing would invent an intention.
      expect(result.exitCode, 64);
      expect(result.err, contains('fabrica, lab'));
    });

    test('no channel at all is absence — 1', () async {
      floor.here = const [];

      final result = await run(['where']);

      expect(result.exitCode, 1);
      expect(result.err, contains('no channel here'));
    });

    test('standing outside the installation is absence, never a stack trace',
        () async {
      // Found by hand and not by this suite: from a directory with no
      // `bentos.chat` above it, the primitive throws and the process left exit
      // 255 with fourteen frames of Dart where one sentence belonged. **A
      // coreutil never exits by stack trace.**
      floor.throwsNotInstalled = true;

      final result = await run(['where'], cwd: '/tmp');

      expect(result.exitCode, 1);
      expect(result.err, startsWith('bentos.chat: '));
      expect(result.err, contains('not installed'));
      expect(result.err, isNot(contains('#0')));
    });

    test('a coordinate of another ontology is a mistake, never a channel',
        () async {
      final result = await run(['-c', 'bentos.llm:sessao', 'where']);

      expect(result.exitCode, 64);
      expect(result.err, contains('not a channel of this ontology'));
    });

    test('-C moves the vantage, and a relative one resolves against the cwd',
        () async {
      await run(['-C', 'workshop', 'where'], cwd: '/campus');

      expect(floor.vantages, everyElement('/campus/workshop'));
    });
  });

  group('speaking', () {
    test('the text is the argument', () async {
      await seated();

      await run(['say', 'raising the install gate']);

      expect(
        floor.tree.files.values,
        anyElement(contains('raising the install gate')),
      );
    });

    test('and stdin when there is none — a pipe is ordinary', () async {
      await seated();

      final result = await run(['say'], stdin: 'from a pipe\n');

      expect(result.exitCode, 0);
      expect(floor.tree.files.values, anyElement(contains('from a pipe')));
    });

    test('an empty pipe is a usage problem and never an empty utterance',
        () async {
      await seated();

      final result = await run(['say'], stdin: '');

      expect(result.exitCode, 64);
      expect(floor.actsDouble.attemptsAt('message'), isEmpty);
    });

    test('a bare topic reads instead of writing', () async {
      await seated();
      await run(['topic', 'the install gate']);

      final result = await run(['topic']);

      expect(result.lines.single, 'the install gate');
      // One write, and the read added none.
      expect(floor.actsDouble.attemptsAt('topic'), hasLength(1));
    });
  });

  group('reading', () {
    test('the roster is one record per line, tab-separated', () async {
      await run(['join', '--name', 'Alfred']);

      final result = await run(['roster']);

      expect(result.lines.single, '@alfred\tAlfred\there');
    });

    test('away rides in the same field, with its reason', () async {
      await run(['join', '--name', 'Alfred']);
      await run(['away', 'at the dentist']);

      final result = await run(['roster']);

      expect(result.lines.single, '@alfred\tAlfred\taway: at the dentist');
    });

    test('the transcript is time, handle, body', () async {
      await seated();
      await run(['say', 'hello']);

      final result = await run(['history']);

      expect(result.lines.single, '2026-08-06T12:00:00.000Z\t@alfred\thello');
    });

    test('a body that spans lines keeps its shape under the header', () async {
      await seated();
      await run(['say', 'first\nsecond']);

      final result = await run(['history']);

      expect(result.lines.first, endsWith('\t@alfred\tfirst'));
      expect(result.lines.last, '\t\tsecond');
    });

    test('--since takes an ISO-8601 moment, and teaches when it does not',
        () async {
      final result = await run(['history', '--since', 'yesterday']);

      expect(result.exitCode, 64);
      expect(result.err, contains('ISO-8601'));
      // A face that merely refused would leave the caller guessing at a syntax
      // nobody wrote down.
      expect(result.err, contains('2026-08-06'));
    });

    test('--limit takes a count', () async {
      final result = await run(['history', '--limit', 'lots']);

      expect(result.exitCode, 64);
      expect(result.err, contains('--limit'));
    });

    test('--as-of reaches the tree, and is not quietly the present', () async {
      await seated();
      await run(['say', 'hello']);
      floor.tree.readsAt.clear();

      await run(['roster', '--as-of', 'c100000']);

      expect(floor.tree.readsAt, isNotEmpty);
      expect(floor.tree.readsAt, everyElement('c100000'));
    });
  });

  group('the gate that is not a channel method', () {
    test('check runs the entity\'s own function and passes its number back',
        () async {
      floor.bodyDouble.answers(
        'check',
        exitCode: 3,
        stderr: 'check: 01K001.md says @cafe, the commit says @alfred',
      );

      final result = await run(['check']);

      expect(result.exitCode, 3);
      expect(result.err, contains('the commit says @alfred'));
      expect(floor.bodyDouble.callsTo('check'), hasLength(1));
      // It carries no seat and answers nobody, so it never opened a channel.
      expect(floor.opened, isEmpty);
    });

    test('a clean check exits 0', () async {
      floor.bodyDouble.answers('check', exitCode: 0);

      expect((await run(['check'])).exitCode, 0);
    });
  });

  group('watching', () {
    test('--once returns instead of blocking, and starts at the tip', () async {
      await seated();
      await run(['say', 'hello']);

      final result = await run(['monitor', '--once']);

      // Watching begins now: a monitor given no `--history` is not a second
      // spelling of `history`, and dumping a conversation somebody has been in
      // all day is the opposite of what they asked for.
      expect(result.exitCode, 0);
      expect(result.out, isEmpty);
    });

    test('--history is the only thing that prints the past', () async {
      await seated();
      await run(['say', 'hello']);

      final result = await run(['monitor', '--once', '--history', '10']);

      expect(result.out, contains('hello'));
    });

    test('the backlog is not printed twice as an event', () async {
      await seated();
      await run(['say', 'hello']);

      final result = await run(['monitor', '--once', '--history', '10']);

      // Printed once as backlog; the cursor was wound to the tip before
      // watching, so it must not arrive again as news.
      expect('hello'.allMatches(result.out), hasLength(1));
    });

    test('--interval takes seconds', () async {
      final result = await run(['monitor', '--interval', 'often']);

      expect(result.exitCode, 64);
      expect(result.err, contains('--interval'));
    });

    test('given, --interval is accepted but warns it no longer paces anything',
        () async {
      final result = await run(['monitor', '--once', '--interval', '5']);

      expect(result.exitCode, 0);
      expect(result.err, contains('--interval'));
    });

    test('unmentioned, --interval draws no warning', () async {
      final result = await run(['monitor', '--once']);

      expect(result.err, isEmpty);
    });

    test('the watch wakes on a dispatch tick, not on a fixed cadence',
        () async {
      await seated();
      final ticker = FakeTicker();
      floor.ticker = ticker;

      final out = StringBuffer();
      final face = ChatRunner(
        out: out,
        err: StringBuffer(),
        currentDirectory: '/campus',
        environment: const {},
        readStdin: () async => '',
        floor: floor,
      );
      final pending = face.run(['monitor']);

      // Let the watch perform its initial sync and start waiting on the
      // doorbell before anything lands.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await run(['say', 'woke by the doorbell']);
      ticker.tick();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(out.toString(), contains('woke by the doorbell'));

      // Closing the doorbell is the only way this loop, given no --once,
      // ever returns — proving the wait afterward and freeing the future.
      ticker.dispose();
      await pending.timeout(const Duration(seconds: 2));
    });
  });
}
