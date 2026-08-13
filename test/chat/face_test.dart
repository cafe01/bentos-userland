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
import 'dart:io';

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

  /// The bound the channels this floor opens are built with.
  ///
  /// **Lowered by any fixture that means to exhaust it**, since a loser waits
  /// real backoff between attempts and the shipped bound would be bought in
  /// wall clock. Nothing about *what a stumble is* depends on the number; that
  /// the shipped one carries a live room is a material claim, measured by the
  /// storm gate and not here.
  int attempts = defaultAttempts;

  /// Who each opened channel was signed under, in order.
  final List<Identity> signed = [];

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
    final signer = identity ?? this.identity;
    // **Honoured, not discarded.** A double that always signed as its own
    // [identityDouble] could not tell a face that passes a stated identity
    // from one that ignores it, which is the whole claim `--identity` makes.
    signed.add(signer);
    actsDouble.identity = signer;
    actsDouble.channel = name;
    return channelConstruction(
      name: name,
      acts: actsDouble,
      tree: tree,
      identity: signer,
      ticker: () => ticker,
      cursor: cursor,
      attempts: attempts,
      // Fixed, so the printed lines this gate judges do not move with the
      // wall clock — the same instant the retired shell's doubles hard-coded.
      clock: () => DateTime.utc(2026, 8, 6, 12),
    );
  }

  @override
  ChatBodies bodies(String name, {required String place, Identity? identity}) {
    vantages.add(place);
    // The seatless gate signs too, so who it was asked under is a fact this
    // double has to be able to report.
    bodiesIdentity = identity ?? this.identity;
    return bodyDouble;
  }

  /// Who [bodies] was last asked for, so a claim that one invocation has one
  /// signer covers the verb that is not a channel method.
  Identity? bodiesIdentity;

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
  late Directory stateDir;
  late File cursorFile;

  setUp(() {
    floor = FakeFloor();
    // **Given, never defaulted.** Two verbs of this face persist a drain mark,
    // and left to itself the default resolves under `$HOME` — absent in a test
    // environment, so it landed on `./.local/state/` in the package itself.
    // That file survived the process: one test's mark decided the next test's
    // batch, and the whole suite's, run after run. A gate reading state no
    // fixture wrote is measuring nothing it can name.
    stateDir = Directory.systemTemp.createTempSync('chat-face-state-');
    cursorFile = File('${stateDir.path}/monitor-state.json');
  });

  tearDown(() => stateDir.deleteSync(recursive: true));

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
      monitorCursorFile: cursorFile,
    );
    await face.run(args);
    return Run(face.exitCode, out.toString(), err.toString());
  }

  /// Seats the caller, so the gate under every writing body is satisfied and a
  /// claim about `say` is about `say`.
  Future<void> seated() => run(['join']);

  /// Somebody else's line, landed straight on the tree — speech this face's
  /// caller did not write and has therefore never read.
  void speak(
    String body, {
    String email = 'cafe@bentos.life',
    String name = 'Café',
  }) {
    final n = 'm${floor.tree.acts.length + 1}';
    floor.tree.land(
      noun: 'message',
      authorName: name,
      authorEmail: email,
      writes: {
        '$messagesPath/2026/08/06/$n.md': 'author: $name <$email>\n\n$body\n',
      },
    );
  }

  group('the exit table', () {
    test('an act that lands exits 0 and prints a labelled receipt', () async {
      final result = await run(['join']);

      expect(result.exitCode, 0);
      // Labelled, because a bare forty-hex line is indistinguishable from a
      // cursor or a position at the call site, and a participant holding
      // nothing but --help cannot ask what it was handed.
      expect(result.lines.first, 'commit\tc100000');
      expect(result.err, isEmpty);
    });

    test('the receipt is the first line of stdout for every act', () async {
      // The position is the contract: whatever else a verb says about the
      // room, a script reading one line reads the receipt.
      await seated();

      for (final act in [
        ['say', 'hello'],
        ['topic', 'the install gate'],
        ['away', 'at the dentist'],
        ['back'],
        ['leave'],
      ]) {
        final result = await run(act);

        expect(result.exitCode, 0, reason: act.first);
        expect(
          result.lines.first.split('\t').first,
          'commit',
          reason: '${act.first} opened with something other than its receipt',
        );
        expect(result.lines.first.split('\t')[1], isNotEmpty);
      }
    });

    test('an act that does not land prints no receipt at all', () async {
      // A caller that greps for the label must never find one over speech
      // that never happened.
      floor.tree.birth();

      final result = await run(['say', 'hello']);

      expect(result.exitCode, 3);
      expect(result.out, isEmpty);
    });

    test('the manual states what the receipt is and what reads it', () async {
      // R4.5: the help text is the whole manual a mind gets, so a value it
      // prints and never names does not exist for the next participant.
      final manual = ChatRunner(floor: floor).manual;

      expect(manual, contains('commit<TAB><sha>'));
      expect(manual, contains('--as-of'));
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
      floor.attempts = 4;
      floor.actsDouble.contestNext('message', 4);

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
      floor.attempts = 4;
      floor.actsDouble.contestNext('message', 4);

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

  group('finding where everybody is', () {
    test('channels lists what the installation carries, one per line',
        () async {
      floor.here = ['dogfood', 'fabrica', 'front-chat'];

      final result = await run(['channels']);

      expect(result.exitCode, 0);
      expect(result.lines, ['dogfood', 'fabrica', 'front-chat']);
    });

    test('an installation with no channels answers, rather than failing',
        () async {
      floor.here = [];

      final result = await run(['channels']);

      expect(result.exitCode, 0);
      expect(result.out, isEmpty);
    });

    test('it answers without a channel being resolvable — the whole point is '
        'asking from outside one', () async {
      floor.here = ['one', 'two'];

      // Two candidates and no -c: every other verb exits 64 here.
      final result = await run(['channels']);

      expect(result.exitCode, 0);
      expect(result.lines, ['one', 'two']);
    });

    test('-C asks of the place named, not of the working directory', () async {
      await run(['-C', '/elsewhere', 'channels']);

      expect(floor.vantages, contains('/elsewhere'));
    });
  });

  group('stating who is speaking', () {
    // The face is reachable through surfaces that have argv and stdin and
    // nothing else — a model calling the coreutil as one tool has no shell to
    // export a variable from. A face that could only be told who is speaking
    // through the environment was unusable from there, and `join` is the first
    // act, so the whole medium was.

    test('--identity states the speaker where the floor refuses to guess one',
        () async {
      floor.refusesIdentity = true;

      final result = await run(
        ['--identity', 'Alfred <alfred@bentos.life>', 'join'],
      );

      expect(result.exitCode, 0);
      expect(floor.signed.single.handle.email, 'alfred@bentos.life');
      expect(floor.signed.single.displayName, 'Alfred');
    });

    test('a bare address is an identity, exactly as the variable spells it',
        () async {
      floor.refusesIdentity = true;

      final result = await run(['--identity', 'peer@bentos.life', 'join']);

      expect(result.exitCode, 0);
      expect(floor.signed.single.handle.email, 'peer@bentos.life');
      expect(floor.signed.single.displayName, isNull);
    });

    test('without it, a floor that will not say who I am still refuses',
        () async {
      floor.refusesIdentity = true;

      final result = await run(['join']);

      expect(result.exitCode, 1);
      expect(result.err, contains('states its own identity'));
      expect(floor.signed, isEmpty);
    });

    test('one invocation has one signer: the gate that carries no seat is '
        'asked under the same identity the channel signs with', () async {
      floor.refusesIdentity = true;

      await run(['--identity', 'peer@bentos.life', 'check']);

      expect(floor.bodiesIdentity?.handle.email, 'peer@bentos.life');
    });
  });

  group('arriving', () {
    test('join answers who is here, under the receipt', () async {
      // A being that enters and is told only a sha announces itself into the
      // dark. The receipt still comes first, so a script reading one line is
      // untouched.
      final result = await run(['join', '--name', 'Alfred']);

      expect(result.exitCode, 0);
      expect(result.lines.first, 'commit\tc100000');
      expect(result.lines[1], 'roster\t@alfred\tAlfred\there');
    });

    test('a room already occupied is listed whole to whoever walks in',
        () async {
      await run(['--identity', 'Café <cafe@bentos.life>', 'join', '--name', 'Café']);

      final result = await run(
        ['--identity', 'Alfred <alfred@bentos.life>', 'join', '--name', 'Alfred'],
      );

      expect(
        result.lines.skip(1),
        containsAll(<String>[
          'roster\t@cafe\tCafé\there',
          'roster\t@alfred\tAlfred\there',
        ]),
      );
    });

    test('presence rides in the record, so away is visible on arrival',
        () async {
      await run(['--identity', 'Café <cafe@bentos.life>', 'join', '--name', 'Café']);
      await run(['--identity', 'Café <cafe@bentos.life>', 'away', 'at the dentist']);

      final result = await run(['--identity', 'alfred@bentos.life', 'join']);

      expect(
        result.lines.skip(1),
        anyElement('roster\t@cafe\tCafé\taway: at the dentist'),
      );
    });

    test('a join that does not land lists nobody', () async {
      // Nothing was entered, so there is no room to report — and a caller
      // greping for presence must not find any over an act that failed.
      floor.tree.birth();
      floor.actsDouble.barNext('membership', 'no');

      final result = await run(['join']);

      expect(result.exitCode, 3);
      expect(result.out, isEmpty);
    });

    test('the manual says join answers presence', () async {
      final manual = ChatRunner(floor: floor).manual;

      expect(manual, contains('roster<TAB>@handle'));
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
    test('--once returns instead of blocking, and hands over what it drained',
        () async {
      // Somebody else was here first, and this caller has never read the room.
      speak('hello');
      await seated();

      final result = await run(['monitor', '--once']);

      expect(result.exitCode, 0);
      expect(result.out, contains('hello'));
    });

    test('a second drain hands over only what landed since the first',
        () async {
      speak('hello');
      await seated();
      await run(['monitor', '--once']);

      speak('still here?');
      final result = await run(['monitor', '--once']);

      // The half that rots in silence: a drain that keeps re-reading the room
      // looks correct at the first call and is useless at every call after.
      expect(result.out, contains('still here?'));
      expect(result.out, isNot(contains('hello')));
    });

    test('a drain that finds nothing new prints nothing and stays quiet',
        () async {
      speak('hello');
      await seated();
      await run(['monitor', '--once']);

      final result = await run(['monitor', '--once']);

      expect(result.exitCode, 0);
      expect(result.out, isEmpty);
    });

    test('--history prints the past beside the drain, each answering its own '
        'question', () async {
      speak('hello');
      await seated();
      await run(['monitor', '--once']);

      final result = await run(['monitor', '--once', '--history', '10']);

      // Nothing is new, so the backlog is the whole output: `--history` keeps
      // its meaning and does not become a second spelling of the drain.
      expect(result.out, contains('hello'));
      expect('hello'.allMatches(result.out), hasLength(1));
    });

    test('a drain under --mention never marks read what it kept off stdout',
        () async {
      speak('nothing to do with you');
      await seated();

      final filtered = await run(['monitor', '--once', '--mention']);
      final everything = await run(['monitor', '--once']);

      // The predicate withheld the line, so the mark may not claim it was
      // read: the next unfiltered drain must still carry it. Advancing here
      // would lose speech silently, which is the one thing a mark must never
      // do — the same refusal `say` already makes over unread speech.
      expect(filtered.out, isNot(contains('nothing to do with you')));
      expect(everything.out, contains('nothing to do with you'));
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
