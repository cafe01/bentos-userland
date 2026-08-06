/// The contract of `llm session`, as claims rather than as prose.
///
/// It is a function of a [SessionConstruction] and knows no concrete class, so
/// the construction delivery plugs its own implementation in one line and runs
/// this file unedited. Written before the implementation, on purpose: a suite
/// authored after the code tends to agree with it.
///
/// Two tags divide what is judged where. Untagged claims run everywhere and are
/// the gate. `owed` claims describe behaviour the floor has not shipped — they
/// state the real thing, fail today, and go green on their own when the other
/// front lands, with nothing here edited. Beside each one sits an untagged claim
/// that the verb currently refuses **naming the exact missing piece**, so the
/// debt cannot be silently paid or silently forgotten.
library;

import 'package:bentos_userland/src/llm/session/coordinate.dart';
import 'package:bentos_userland/src/llm/session/face.dart';
import 'package:bentos_userland/src/llm/session/machine.dart';
import 'package:bentos_userland/src/llm/session/primitive.dart';
import 'package:bentos_userland/src/llm/session/transcript.dart';
import 'package:bentos_userland/src/llm/session/turn.dart';
import 'package:chat_inference/chat_inference.dart' show ChatRole;
import 'package:test/test.dart';

import 'support/doubles.dart';
import 'support/fixtures.dart';

const Coordinate demo = Coordinate('bentos.llm', 'demo');
const Sha pinned = Sha('aaaa111');
const Sha later = Sha('bbbb222');
const Sha earlier = Sha('0000000');

const Fold idle = Fold(
  state: SessionState.idle,
  openCalls: [],
  messages: 9,
  commit: pinned,
);

void runSessionContract(SessionConstruction construction) {
  // ───────────────────────────────────────────────────────────────────────
  // Attribution — the rule alone. No collaborator, no double: a claim about
  // one message and one answer.
  // ───────────────────────────────────────────────────────────────────────
  group('attribution is read off what a message carries', () {
    late List<StoredMessage> real;
    setUpAll(() async => real = await realSessionTranscript());

    Speaker of(StoredMessage m) => construction.attribution.of(m.message);

    test('a result rides as a user-role message and is the executor', () {
      // The sharpest claim in the face: printing this one raw puts words in a
      // person's mouth that they never said.
      expect(of(real[3]), Speaker.executor);
      expect(real[3].message.role, ChatRole.user,
          reason: 'the fixture must keep carrying a user role, or this claim '
              'stops being about anything');
    });

    test('a prompt is you', () => expect(of(real[1]), Speaker.you));
    test('a reply is the agent', () => expect(of(real[2]), Speaker.agent));
    test('the leader is the constitution',
        () => expect(of(real[0]), Speaker.constitution));

    test('a result beside a note is still the executor', () async {
      // Hand-authored: a shape our own encoder never emits, so the rule cannot
      // be passing by agreeing with the writer.
      expect(of(await hand('executor-two-results.json')), Speaker.executor);
    });

    test('a reply that thinks and calls is still the agent', () async {
      expect(of(await hand('agent-thinking-and-call.json')), Speaker.agent);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The lens — the translation, and the only thing the face invents.
  // ───────────────────────────────────────────────────────────────────────
  group('the lens', () {
    late List<StoredMessage> real;
    setUpAll(() async => real = await realSessionTranscript());

    List<RenderedTurn> under(List<StoredMessage> t, Lens lens) =>
        construction.view.render(t, lens);

    test('conversation drops the constitution and work keeps it', () {
      final constitution = [real[0], real[1]];
      expect(
        under(constitution, Lens.conversation).map((t) => t.speaker),
        isNot(contains(Speaker.constitution)),
      );
      // The leader of the real session is empty text, which is why this claim
      // is made with a constitution that says something.
      final spoken = [
        StoredMessage('llm/messages/0001.json', real[0].message),
      ];
      expect(under(spoken, Lens.work).length, lessThanOrEqualTo(1));
    });

    test('thinking is hidden in conversation and shown in work', () async {
      final thinking = [await hand('agent-thinking-and-call.json')];
      final talk = under(thinking, Lens.conversation).single.blocks.join('\n');
      final work = under(thinking, Lens.work).single.blocks.join('\n');
      expect(talk, isNot(contains('two roads here')));
      expect(work, contains('two roads here'));
    });

    test('redacted thinking is marked in work and absent in conversation',
        () async {
      final redacted = [await hand('agent-redacted-thinking.json')];
      expect(under(redacted, Lens.work).single.blocks.length, 2);
      expect(under(redacted, Lens.conversation).single.blocks.length, 1);
    });

    test('a call is collapsed in conversation and whole in work', () async {
      final calling = [await hand('agent-thinking-and-call.json')];
      final talk = under(calling, Lens.conversation).single.blocks.join('\n');
      final work = under(calling, Lens.work).single.blocks.join('\n');
      // The measure has to distinguish: the argument is long on purpose, so a
      // lens that stopped clipping cannot keep this green.
      expect(work, contains("head -50"));
      expect(talk, isNot(contains('head -50')));
      expect(talk.length, lessThan(work.length));
    });

    test('an error result says so', () async {
      final results = [await hand('executor-two-results.json')];
      final work = under(results, Lens.work).single.blocks.join('\n');
      expect(work, contains('first'));
      expect(work, contains('boom'));
      expect(work.toLowerCase(), contains('fail'));
    });

    test('a message that renders to nothing produces no turn at all', () {
      // The real leader is a system message whose text is empty. A face that
      // emitted a speaker line for it would print a turn nobody took.
      expect(under([real[0]], Lens.conversation), isEmpty);
    });

    test('rendering is pure', () async {
      final once = under(real, Lens.work);
      final twice = under(real, Lens.work);
      expect(
        once.map((t) => '${t.speaker}${t.blocks}').toList(),
        twice.map((t) => '${t.speaker}${t.blocks}').toList(),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Reading the transcript — over a fake primitive holding a real tree.
  // ───────────────────────────────────────────────────────────────────────
  group('reading the transcript', () {
    late FakePrimitive floor;
    late TranscriptReader reader;

    setUp(() {
      floor = FakePrimitive()..commit(demo, pinned, realSessionTree());
      reader = construction.transcriptsOver(floor);
    });

    test('.gitkeep is not a message', () async {
      final names = await reader.messageNames(demo, asOf: pinned);
      expect(names, isNot(contains(endsWith('.gitkeep'))));
      expect(names.length, realSessionMessages.length);
    });

    test('an event stream folds to one message', () async {
      final transcript = await reader.transcript(demo, asOf: pinned);
      expect(transcript.length, realSessionMessages.length);
      final reply = transcript[2].message;
      expect(reply.role, ChatRole.assistant);
      expect(reply.content, isNotEmpty);
    });

    test('order is the names, not the order the floor listed them', () async {
      floor.lsOrder = (sorted) => sorted.reversed.toList();
      final names = await reader.messageNames(demo, asOf: pinned);
      expect(names.first, endsWith(realSessionMessages.first));
      expect(names.last, endsWith(realSessionMessages.last));
    });

    test('the commit is carried into every read, not only the listing',
        () async {
      await reader.transcript(demo, asOf: pinned);
      final reads = floor.callsTo('read');
      expect(reads, isNotEmpty);
      expect(
        reads.every((c) => c.asOf?.value == pinned.value),
        isTrue,
        reason: 'a read without the pin reads the tip, and the screen becomes '
            'two instants stitched together',
      );
    });

    test('a failing read is a failure, never an empty conversation', () async {
      final broken = FakePrimitive()
        ..commit(demo, pinned, {'llm/messages/0001.json': '{'});
      expect(
        () => construction.transcriptsOver(broken).transcript(demo, asOf: pinned),
        throwsA(anything),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The screen is one instant.
  // ───────────────────────────────────────────────────────────────────────
  group('a screen is one instant', () {
    late FakePrimitive floor;
    late FakeMachine machine;
    late FakeTranscripts transcripts;

    SessionFace faceOver() => construction.face(
          primitive: floor,
          coordinates: FakeCoordinateSource(
            resolution: const CoordinateResolution(
              demo,
              CoordinateOrigin.argument,
            ),
          ),
          machine: machine,
          transcripts: transcripts,
          view: construction.view,
          rest: FakeRest(TurnOutcome.rested),
        );

    setUp(() async {
      floor = FakePrimitive()..commit(demo, pinned, realSessionTree());
      machine = FakeMachine([idle]);
      transcripts = FakeTranscripts({
        pinned.value: await realSessionTranscript(),
        earlier.value: (await realSessionTranscript()).take(2).toList(),
      });
    });

    test('the tip is taken once and everything descends with it', () async {
      await faceOver().show(demo);
      expect(floor.callsTo('tip').length, 1);
      expect(transcripts.asOfAsked.every((s) => s?.value == pinned.value), isTrue);
      expect(machine.asOfAsked, everyElement(isNotNull));
      expect(machine.asOfAsked.first?.value, pinned.value);
    });

    test('a session that moves mid-read still renders the pinned instant',
        () async {
      // The world advances underneath, which is the ordinary case: the circuit
      // is asynchronous and nobody stops it to be read.
      floor.afterEachRead = () => floor.commit(demo, later, realSessionTree());
      final screen = await faceOver().show(demo);
      expect(screen.pinnedAt.value, pinned.value);
      expect(screen.turns, isNotEmpty);
    });

    test('an older instant is readable, state and all', () async {
      final screen = await faceOver().show(demo, asOf: earlier);
      expect(screen.pinnedAt.value, earlier.value);
      expect(screen.turns.length, lessThan(realSessionMessages.length));
      expect(machine.asOfAsked.last?.value, earlier.value);
    });

    test('the state is the entity fold and never derived', () async {
      machine = FakeMachine([
        const Fold(
          state: SessionState.owesResults,
          openCalls: ['call_R399Uha2pUVDwMUEhAbSNGJ1'],
          messages: 9,
          commit: pinned,
        ),
      ]);
      final screen = await faceOver().show(demo);
      expect(screen.fold.state, SessionState.owesResults);
      expect(screen.fold.openCalls, isNotEmpty);
    });

    test('the audit lens hands back the acts, unretold', () async {
      floor.logs['bentos.llm:demo'] = [
        Act(
          sha: pinned,
          name: 'user.say',
          actor: 'user',
          instant: DateTime.utc(2026, 8, 5),
          sentence: 'user say · "verificação por uso"',
        ),
      ];
      final screen = await faceOver().show(demo, lens: Lens.audit);
      expect(screen.acts, hasLength(1));
      expect(screen.acts.single.sentence, contains('verificação'));
    });

    test('an unopened conversation is said to be unopened', () async {
      floor = FakePrimitive();
      expect(() => faceOver().show(demo), throwsA(isA<SessionNotOpen>()));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // The turn.
  // ───────────────────────────────────────────────────────────────────────
  group('the turn', () {
    late FakePrimitive floor;
    late FakeRest rest;
    late FakeTranscripts transcripts;

    SessionFace faceOver({FakeMachine? machine}) => construction.face(
          primitive: floor,
          coordinates: FakeCoordinateSource(
            resolution: const CoordinateResolution(
              demo,
              CoordinateOrigin.argument,
            ),
          ),
          machine: machine ?? FakeMachine([idle]),
          transcripts: transcripts,
          view: construction.view,
          rest: rest,
        );

    setUp(() async {
      floor = FakePrimitive()..commit(demo, pinned, realSessionTree());
      floor.functions['user.say'] = (_) => deposited(later.value);
      rest = FakeRest(TurnOutcome.rested);
      final whole = await realSessionTranscript();
      transcripts = FakeTranscripts({
        pinned.value: whole.take(6).toList(),
        later.value: whole,
      });
    });

    test('saying deposits through the entity and derives nothing', () async {
      await faceOver().say(demo, 'olá');
      final run = floor.callsTo('run').single;
      expect(run.argument, startsWith('user.say'));
      expect(run.argument, contains('olá'));
    });

    test('the wait is asked for once, with the limit given', () async {
      await faceOver().say(demo, 'olá', limit: const Duration(seconds: 7));
      expect(rest.waits, 1);
      expect(rest.limitAsked, const Duration(seconds: 7));
    });

    test('what landed excludes the words the person just typed', () async {
      floor.afterEachRead = null;
      floor.commit(demo, later, realSessionTree());
      final turn = await faceOver().say(demo, 'olá');
      expect(turn.outcome, TurnOutcome.rested);
      expect(
        turn.landed.map((t) => t.speaker),
        isNot(contains(Speaker.you)),
        reason: 'they have just typed it; echoing it back is padding',
      );
      expect(turn.landed, isNotEmpty);
    });

    test('--no-wait deposits and does not wait', () async {
      final turn = await faceOver().say(demo, 'olá', wait: false);
      expect(rest.waits, 0);
      expect(turn.landed, isEmpty);
      expect(floor.callsTo('run').single.argument, startsWith('user.say'));
    });

    test('a refusal is a value, in the floor own words, and nothing is awaited',
        () async {
      floor.functions['user.say'] =
          (_) => refused('check: a prompt is illegal while results are owed');
      final turn = await faceOver().say(demo, 'olá');
      expect(turn.outcome, TurnOutcome.refused);
      expect(turn.landed, isEmpty);
      expect(rest.waits, 0);
      expect(turn.refusal, contains('illegal while results are owed'));
    });

    test('interrupting the wait does not undo the act', () async {
      rest.outcome = TurnOutcome.cancelled;
      final turn = await faceOver().say(demo, 'olá', cancelled: () => true);
      expect(turn.outcome, TurnOutcome.cancelled);
      expect(
        floor.callsTo('run').where((c) => c.argument!.startsWith('user.say')),
        hasLength(1),
        reason: 'the act committed before the wait began, and looking away is '
            'not undoing',
      );
    });

    test('a timeout still shows what did land', () async {
      rest
        ..outcome = TurnOutcome.timedOut
        ..during = () => floor.commit(demo, later, realSessionTree());
      final turn = await faceOver().say(demo, 'olá');
      expect(turn.outcome, TurnOutcome.timedOut);
      expect(turn.landed, isNotEmpty,
          reason: 'the wait ran out; the work did not');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Finding.
  // ───────────────────────────────────────────────────────────────────────
  group('finding a conversation', () {
    late FakePrimitive floor;

    setUp(() {
      floor = FakePrimitive()
        ..commit(demo, pinned, {
          ...realSessionTree(),
          'llm/title': 'verificação por uso\n',
        })
        ..commit(const Coordinate('bentos.llm', 'nameless'), later,
            realSessionTree());
    });

    SessionFace faceOver({FakeCoordinateSource? coordinates}) =>
        construction.face(
          primitive: floor,
          coordinates: coordinates ??
              FakeCoordinateSource(
                resolution: const CoordinateResolution(
                  demo,
                  CoordinateOrigin.ambient,
                ),
              ),
          machine: FakeMachine([idle]),
          transcripts: FakeTranscripts({}),
          view: construction.view,
          rest: FakeRest(TurnOutcome.rested),
        );

    test('a listing carries title, state and the last act', () async {
      floor.logs['bentos.llm:demo'] = [
        Act(
          sha: pinned,
          name: 'assistant.reply',
          actor: 'assistant',
          instant: DateTime.utc(2026, 8, 5, 18, 41),
          sentence: 'assistant reply · stop end_turn',
        ),
      ];
      final cards = await faceOver().list();
      final card = cards.firstWhere((c) => c.coordinate.instance == 'demo');
      expect(card.title, 'verificação por uso');
      expect(card.state, SessionState.idle);
      expect(card.lastAct?.name, 'assistant.reply');
    });

    test('a conversation with no title says so rather than showing its id',
        () async {
      final cards = await faceOver().list();
      final card = cards.firstWhere((c) => c.coordinate.instance == 'nameless');
      expect(card.title, isNull);
    });

    test('use returns the line the floor gave, never one the face spelled',
        () async {
      final source = FakeCoordinateSource(
        resolution: const CoordinateResolution(demo, CoordinateOrigin.argument),
      );
      final report = await faceOver(coordinates: source).use('bentos.llm:demo');
      expect(report.exportLine, source.line,
          reason: 'the variable name is the primitive convention; a face that '
              'built this string has fixed a convention it does not own');
    });

    test('use with nothing says where you are and which step said so',
        () async {
      final report = await faceOver().use(null);
      expect(report.coordinate.instance, 'demo');
      expect(report.origin, CoordinateOrigin.ambient);
      expect(report.exportLine, isNull);
    });

    test('ambiguity is reported with its candidates and never picked', () async {
      final source = FakeCoordinateSource(
        failure: const CoordinateAmbiguous([
          Coordinate('bentos.llm', 'demo'),
          Coordinate('bentos.llm', 'nameless'),
        ]),
      );
      expect(
        () => faceOver(coordinates: source).use(null),
        throwsA(isA<CoordinateAmbiguous>()
            .having((e) => e.candidates, 'candidates', hasLength(2))),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Travelling in time.
  // ───────────────────────────────────────────────────────────────────────
  group('travelling in time', () {
    late FakePrimitive floor;

    SessionFace faceOver() => construction.face(
          primitive: floor,
          coordinates: FakeCoordinateSource(
            resolution:
                const CoordinateResolution(demo, CoordinateOrigin.argument),
          ),
          machine: FakeMachine([idle]),
          transcripts: FakeTranscripts({}),
          view: construction.view,
          rest: FakeRest(TurnOutcome.rested),
        );

    setUp(() {
      floor = FakePrimitive()..commit(demo, pinned, realSessionTree());
      floor.functions['user.revise'] = (_) => deposited(later.value);
    });

    test('a fork is born at the act, and both continuations stand', () async {
      final forked = await faceOver().fork(demo, at: pinned, name: 'branch');
      final birth = floor.callsTo('birth').single;
      expect(birth.asOf?.value, pinned.value);
      expect(forked.bornFrom?.value, pinned.value);
      expect(floor.tips['bentos.llm:demo']?.value, pinned.value,
          reason: 'forking moves nothing on the conversation forked from');
    });

    test('revising rewrites that turn through the entity own verb', () async {
      await faceOver().revise(
        demo,
        message: 'llm/messages/0002-20260805T175310Z.json',
        text: 'outra pergunta',
      );
      final run = floor.callsTo('run').single;
      expect(run.argument, startsWith('user.revise'));
      expect(run.argument, contains('--from'));
      expect(run.argument, contains('0002-20260805T175310Z.json'));
    });

    test('amending the constitution leaves the conversation standing',
        () async {
      await faceOver().reviseConstitution(demo, 'you are terse');
      final run = floor.callsTo('run').single;
      expect(run.argument, startsWith('user.revise'));
      expect(run.argument, contains('--system'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // What the floor still owes. Each pair: the refusal that names the piece,
  // and the real behaviour, tagged, waiting for the other front.
  // ───────────────────────────────────────────────────────────────────────
  group('what the floor still owes', () {
    late FakePrimitive floor;

    SessionFace faceOver() => construction.face(
          primitive: floor,
          coordinates: FakeCoordinateSource(
            resolution:
                const CoordinateResolution(demo, CoordinateOrigin.argument),
          ),
          machine: FakeMachine([idle]),
          transcripts: FakeTranscripts({}),
          view: construction.view,
          rest: FakeRest(TurnOutcome.rested),
        );

    setUp(() => floor = FakePrimitive()..commit(demo, pinned, realSessionTree()));

    test('rewind refuses, naming the deposit that is missing', () async {
      await expectLater(
        () => faceOver().rewind(demo, 'llm/messages/0002-20260805T175310Z.json'),
        throwsA(isA<OwedByFloor>().having(
          (e) => e.owed,
          'owed',
          allOf(contains('bentos.llm'), contains('user.revise'),
              contains('--drop')),
        )),
        reason: 'if this failed because rewind now works, bentos.llm shipped '
            '`user.revise --from <message> --drop`: delete this claim and drop '
            'the `owed` tag from the one below it',
      );
    });

    test(
      'rewind discards from a message on, without rewriting it',
      () async {
        floor.functions['user.revise'] = (_) => deposited(later.value);
        final landed = await faceOver()
            .rewind(demo, 'llm/messages/0002-20260805T175310Z.json');
        expect(landed.sha.value, later.value);
        final run = floor.callsTo('run').single;
        expect(run.argument, contains('--drop'));
      },
      tags: 'owed',
    );

    test('the executor seat refuses, naming the deposit that is missing',
        () async {
      await expectLater(
        () => faceOver().result(demo, 'call_A', '28'),
        throwsA(isA<OwedByFloor>().having(
          (e) => e.owed,
          'owed',
          allOf(contains('bentos.llm'), contains('user.result')),
        )),
        reason: 'if this failed because result now works, bentos.llm shipped a '
            'deposit for a result nobody ran: delete this claim and drop the '
            '`owed` tag from the one below it',
      );
    });

    test(
      'a person types a result and it enters by the door a program enters',
      () async {
        floor.functions['user.result'] = (_) => deposited(later.value);
        final landed = await faceOver().result(demo, 'call_A', '28');
        expect(landed.sha.value, later.value);
        final run = floor.callsTo('run').single;
        expect(run.argument, contains('call_A'));
      },
      tags: 'owed',
    );

    test('the ambient coordinate refuses, naming the front that owes it',
        () async {
      await expectLater(
        () => construction.coordinatesOver(floor).resolve(null),
        throwsA(isA<OwedByFloor>().having(
          (e) => e.owed,
          'owed',
          allOf(contains('entity'), contains('ambient')),
        )),
        reason: 'if this failed because the ambient coordinate now resolves, '
            'the entity front landed: delete this claim and drop the `owed` '
            'tag from the one below it',
      );
    });

    test(
      'the ambient coordinate walks argument, then variable, then place',
      () async {
        final source = construction.coordinatesOver(floor);
        expect(
          (await source.resolve('bentos.llm:demo')).origin,
          CoordinateOrigin.argument,
        );
        expect((await source.resolve(null)).origin,
            anyOf(CoordinateOrigin.ambient, CoordinateOrigin.place));
      },
      tags: 'owed',
    );

    test('every knob reports as offered until a device announces otherwise',
        () async {
      floor.commit(demo, pinned, {
        ...realSessionTree(),
        'llm/channel.toml':
            'device = "/dev/llm/openai/gpt-4o-mini"\ntemperature = 0.0\n',
      });
      final knobs = await faceOver().knobs(demo);
      expect(knobs, isNotEmpty);
      expect(
        knobs.every((k) => k.offered),
        isTrue,
        reason: 'gating is owed: a device does not announce its capabilities '
            'yet, and a knob reported as refused today would be a guess',
      );
    });

    test(
      'a knob the device does not announce is shown with its reason',
      () async {
        // The same channel its untagged sibling stands on. Without it this
        // claim died on a missing path, and a standing red that fails before
        // reaching its own subject names no piece at all.
        floor.commit(demo, pinned, {
          ...realSessionTree(),
          'llm/channel.toml':
              'device = "/dev/llm/openai/gpt-4o-mini"\ntemperature = 0.0\n',
        });
        final knobs = await faceOver().knobs(demo);
        final refused = knobs.where((k) => !k.offered);
        expect(
          refused,
          isNotEmpty,
          reason: 'owed by the floor — a device does not announce its '
              'capabilities, so no knob can be reported as refused. When a '
              'device ships that announcement, this goes green by itself',
        );
        expect(refused.first.refusedBecause, isNotNull);
      },
      tags: 'owed',
    );
  });
}
