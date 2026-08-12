/// The contract of a [Channel], judged against the claims and never against a
/// class. Whatever satisfies these is the medium's caller surface.
///
/// **No claim here is tagged `owed`, and nothing here is.** The medium ships
/// every verb this surface names — `leave`, `topic`, `away` and `back` landed
/// with the genesis's second authoring — so every claim is an ordinary one and
/// green is reachable by building rather than by tolerating.
library;

import 'package:bentos_userland/bentos_chat.dart';
import 'package:test/test.dart';

import 'support/doubles.dart';

void runChannelContract(ChannelConstruction construct) {
  late FakeTree tree;
  late FakeBodies bodies;
  late FakeIdentity identity;
  late FakeTicker ticker;

  Channel open({String? cursor, int attempts = defaultAttempts}) => construct(
        name: 'fabrica',
        bodies: bodies,
        tree: tree,
        identity: identity,
        ticker: () => ticker,
        cursor: cursor,
        attempts: attempts,
      );

  /// A member, so that speaking is not refused by the gate.
  void seated([String local = 'alfred']) => tree.land(
        noun: 'membership',
        authorName: 'Alfred',
        authorEmail: '$local@bentos.life',
        writes: {
          '$participantsPath/$local/joined': '2026-08-06T11:00:00Z\n',
          '$participantsPath/$local/name': 'Alfred\n',
        },
      );

  setUp(() {
    tree = FakeTree();
    identity = FakeIdentity();
    bodies = FakeBodies(tree)..identity = identity;
    ticker = FakeTicker();
  });

  group('the address, and who is speaking', () {
    test('the name is the instance id', () {
      expect(open().name, 'fabrica');
    });

    test('the coordinate is the ontology and the name', () {
      expect(open().coordinate, 'bentos.chat:fabrica');
    });

    test('who I am comes from the substrate, never from an argument', () {
      identity.handle = const Handle('cafe', 'bentos.life');
      expect(open().me, const Handle('cafe', 'bentos.life'));
    });
  });

  group('acting maps the body\'s own words', () {
    test('exit 0 is Acted, at the commit the body printed', () async {
      seated();
      final result = await open().say('green');
      expect(result, isA<Acted>());
      expect((result as Acted).commit, isNotEmpty);
    });

    test('exit 3 is Refused, carrying the floor\'s words verbatim', () async {
      // Nobody seated: the one gate of this application.
      final result = await open().say('let me in');
      expect(result, isA<Refused>());
      expect(
        (result as Refused).reason,
        contains('is not in bentos.chat:fabrica'),
      );
    });

    test('exit 75 is Stumbled, and never a refusal', () async {
      bodies.answers('say', exitCode: bodyStumbled, stderr: 'the ref moved');
      expect(await open().say('green'), isA<Stumbled>());
    });

    test('a stumble reports the bound this caller set', () async {
      bodies.answers('say', exitCode: bodyStumbled);
      final result = await open(attempts: 3).say('green');
      expect((result as Stumbled).attempts, 3);
    });

    test('any other failure is neither a decision nor a lost race', () async {
      bodies.answers('say', exitCode: bodyUsage, stderr: 'say: nothing to say');
      expect(open().say(''), throwsA(isA<ChatFailure>()));
    });
  });

  group('the bound travels down, and the library does not retry', () {
    test('every act hands the bodies the bound', () async {
      seated();
      await open(attempts: 5).say('green');
      expect(bodies.callsTo('say').single.attempts, 5);
    });

    test('the default bound is the one the bodies default to', () async {
      seated();
      await open().say('green');
      expect(bodies.callsTo('say').single.attempts, defaultAttempts);
    });

    // THE DISJOINT CLAIM. The retry lives in the body — one loop, minting the
    // ULID before it so every attempt writes the same bytes at the same path.
    // A second loop here would multiply the bound and make the reported
    // attempt count a lie, and nothing but a call count can see it.
    test('a stumble is not retried again by the library', () async {
      bodies.answers('say', exitCode: bodyStumbled);
      await open().say('green');
      expect(bodies.callsTo('say'), hasLength(1));
    });

    test('a refusal is a decision, and a decision is never retried', () async {
      bodies.answers('say', exitCode: bodyRefused, stderr: 'refused');
      await open().say('green');
      expect(bodies.callsTo('say'), hasLength(1));
    });
  });

  group('writing goes through the bodies, reading does not', () {
    test('joining runs the entity\'s own function', () async {
      await open().join(displayName: 'Alfred');
      expect(bodies.callsTo('join'), hasLength(1));
    });

    test('the display name travels as the body\'s flag', () async {
      await open().join(displayName: 'Alfred');
      expect(bodies.callsTo('join').single.arguments, ['--name', 'Alfred']);
    });

    test('speaking passes the text and nothing about who is speaking', () async {
      seated();
      await open().say('green');
      expect(bodies.callsTo('say').single.arguments, ['green']);
    });

    test('the roster spawns no process', () async {
      seated();
      await open().roster();
      expect(bodies.calls, isEmpty);
    });

    test('the transcript spawns no process', () async {
      seated();
      await open().history();
      expect(bodies.calls, isEmpty);
    });

    test('the topic spawns no process', () async {
      seated();
      tree.files[topicPath] = 'the install gate\n';
      await open().topic();
      expect(bodies.calls, isEmpty);
    });
  });

  group('the roster is one listing', () {
    test('it never walks the log', () async {
      seated();
      await open().roster();
      expect(tree.logRead, isFalse);
    });

    test('it answers who is here', () async {
      seated('alfred');
      seated('cafe');
      final roster = await open().roster();
      expect(
        roster.participants.map((p) => p.handle.local).toList()..sort(),
        ['alfred', 'cafe'],
      );
    });

    test('a participant carries what it declared', () async {
      seated();
      final participant = (await open().roster()).byHandle('alfred')!;
      expect(participant.displayName, 'Alfred');
      expect(participant.joined, DateTime.utc(2026, 8, 6, 11));
    });

    test('a handle nobody answers to is null, never an error', () async {
      seated();
      expect((await open().roster()).byHandle('nobody'), isNull);
    });

    test('presence absent is here', () async {
      seated();
      expect((await open().roster()).byHandle('alfred')!.isAway, isFalse);
    });

    test('presence is asked of the path, not of the bytes', () async {
      seated();
      // Away, having said nothing. The file exists and is empty, which is a
      // declaration and not an absence.
      tree.files['$participantsPath/alfred/away'] = '';
      final participant = (await open().roster()).byHandle('alfred')!;
      expect(participant.isAway, isTrue);
      expect(participant.away, '');
    });

    test('and the contents are the reason', () async {
      seated();
      tree.files['$participantsPath/alfred/away'] = 'at the dentist\n';
      expect((await open().roster()).byHandle('alfred')!.away, 'at the dentist');
    });

    test('the substrate\'s own entries are nobody', () async {
      seated();
      // Git carries no empty folder, so the class's structure is kept by a
      // `.gitkeep` every instance inherits and nobody joined as.
      tree.files['$participantsPath/.gitkeep'] = '';
      expect((await open().roster()).participants, hasLength(1));
    });
  });

  group('the transcript is in the order it arrived', () {
    // THE DISJOINT FIXTURE: the clock and the arrival disagree. A transcript
    // sorted by the ULID or by the spoken time passes every other claim here
    // and fails this one, which is the only reason it is written.
    setUp(() {
      seated();
      bodies.spokenTimes.addAll([
        '2026-08-06T12:05:00Z', // spoken later, arrived first
        '2026-08-06T12:01:00Z',
      ]);
    });

    test('position is arrival and not the clock', () async {
      final channel = open();
      await channel.say('raising the install gate');
      await channel.say('green');
      final transcript = await channel.history();
      expect(transcript.map((m) => m.body).toList(),
          ['raising the install gate', 'green']);
    });

    test('a message states its own author', () async {
      final channel = open();
      await channel.say('green');
      expect((await channel.history()).single.author,
          const Handle('alfred', 'bentos.life'));
    });

    test('and the time it was spoken', () async {
      final channel = open();
      await channel.say('green');
      expect((await channel.history()).single.spoken,
          DateTime.utc(2026, 8, 6, 12, 5));
    });

    test('the limit takes the last to arrive', () async {
      final channel = open();
      await channel.say('raising the install gate');
      await channel.say('green');
      final transcript = await channel.history(limit: 1);
      expect(transcript.single.body, 'green');
    });

    test('since and until filter on when it was spoken', () async {
      final channel = open();
      await channel.say('raising the install gate'); // spoken 12:05
      await channel.say('green'); //                    spoken 12:01
      final transcript =
          await channel.history(until: DateTime.utc(2026, 8, 6, 12, 2));
      expect(transcript.single.body, 'green');
    });

    test('a channel nobody spoke in has an empty transcript', () async {
      expect(await open().history(), isEmpty);
    });
  });

  group('the topic', () {
    test('is null when nobody set one', () async {
      seated();
      expect(await open().topic(), isNull);
    });

    test('is the file, trimmed', () async {
      seated();
      tree.files[topicPath] = 'the install gate\n';
      expect(await open().topic(), 'the install gate');
    });
  });

  group('a channel that does not exist', () {
    test('reading the transcript says so', () {
      tree.unborn();
      expect(open().history(), throwsA(isA<NoSuchChannel>()));
    });

    test('reading the roster says so', () {
      tree.unborn();
      expect(open().roster(), throwsA(isA<NoSuchChannel>()));
    });

    // Joining is the one door in: membership opens the channel when the channel
    // does not exist yet, so it is the one verb an unborn channel accepts.
    test('joining it is how it comes to exist', () async {
      tree.unborn();
      expect(await open().join(), isA<Acted>());
    });
  });

  group('leaving', () {
    test('it runs the entity\'s own function', () async {
      seated();
      await open().leave();
      expect(bodies.callsTo('leave').single.arguments, isEmpty);
    });

    test('the seat is gone from the roster', () async {
      seated();
      final channel = open();
      await channel.leave();
      expect((await channel.roster()).participants, isEmpty);
    });

    // THE DISJOINT CLAIM. The roster answers *who is here* and the transcript
    // answers *what was said*: a departed participant is absent from the first
    // and present in the second, and a `leave` that tore down more than the
    // seat would satisfy the claim above and fail this one.
    test('and what was said stays said', () async {
      seated();
      final channel = open();
      await channel.say('raising the install gate');
      await channel.leave();
      expect((await channel.history()).single.body, 'raising the install gate');
      // ASKED OF THE TREE AS WELL, because the transcript alone cannot see it:
      // `history` reads each message at the commit that added it, so it
      // survives a `leave` that deleted every message in the channel. The
      // reading that tells a seat torn down from a channel torn down is the
      // tree's, and a body wide open was caught passing the line above.
      expect(tree.files.keys.where((k) => k.startsWith('$messagesPath/')),
          hasLength(1));
    });

    test('leaving a channel you are not in is refused', () async {
      expect(await open().leave(), isA<Refused>());
    });

    test('and the departure comes back as a roster', () async {
      seated();
      final channel = open();
      await channel.sync();
      await channel.leave();
      expect(await channel.sync(), contains(isA<RosterChanged>()));
    });
  });

  group('the topic', () {
    test('setting it passes the text and nothing else', () async {
      seated();
      await open().setTopic('the install gate');
      expect(bodies.callsTo('topic').single.arguments, ['the install gate']);
    });

    test('it reads back as the file, trimmed', () async {
      seated();
      final channel = open();
      await channel.setTopic('the install gate');
      expect(await channel.topic(), 'the install gate');
    });

    test('a change comes back as the topic, and by whom', () async {
      seated();
      final channel = open();
      await channel.sync();
      await channel.setTopic('green');
      final changed = (await channel.sync()).whereType<TopicChanged>().single;
      expect(changed.topic, 'green');
      expect(changed.by, const Handle('alfred', 'bentos.life'));
    });

    test('a non-member does not set it', () async {
      expect(await open().setTopic('mine now'), isA<Refused>());
    });
  });

  group('presence is declared or absent, never simulated', () {
    test('a reason travels as the body\'s argument', () async {
      seated();
      await open().away('at the dentist');
      expect(bodies.callsTo('away').single.arguments, ['at the dentist']);
    });

    test('and reads back as the reason', () async {
      seated();
      final channel = open();
      await channel.away('at the dentist');
      expect((await channel.roster()).byHandle('alfred')!.away,
          'at the dentist');
    });

    // Away having said nothing is a DECLARATION and not an absence: the field
    // exists and is empty. A body told to write nothing when it was given
    // nothing passes every claim above and fails this one.
    test('away having said nothing is still away', () async {
      seated();
      final channel = open();
      await channel.away();
      expect(bodies.callsTo('away').single.arguments, isEmpty);
      final participant = (await channel.roster()).byHandle('alfred')!;
      expect(participant.isAway, isTrue);
      expect(participant.away, '');
    });

    test('coming back removes the field rather than writing one', () async {
      seated();
      final channel = open();
      await channel.away('at the dentist');
      await channel.back();
      expect((await channel.roster()).byHandle('alfred')!.isAway, isFalse);
    });

    test('and presence comes back as the roster', () async {
      seated();
      final channel = open();
      await channel.sync();
      await channel.away();
      expect(await channel.sync(), contains(isA<RosterChanged>()));
    });

    test('a non-member declares nothing about itself', () async {
      expect(await open().away(), isA<Refused>());
      expect(await open().back(), isA<Refused>());
    });
  });

  group('sync reads from a cursor the caller holds', () {
    test('from nothing, it yields the conversation whole', () async {
      seated();
      final channel = open();
      await channel.say('green');
      expect(await channel.sync(), isNotEmpty);
    });

    test('speech comes back as speech', () async {
      seated();
      final channel = open();
      await channel.say('green');
      final events = await channel.sync();
      expect(events.whereType<Spoke>().single.message.body, 'green');
    });

    test('membership comes back as the roster', () async {
      final channel = open();
      await channel.join();
      expect(await channel.sync(), contains(isA<RosterChanged>()));
    });

    test('it advances the cursor to the tip', () async {
      seated();
      final channel = open();
      await channel.say('green');
      await channel.sync();
      expect(channel.cursor, tree.tip());
    });

    test('a second call with nothing landed yields nothing', () async {
      seated();
      final channel = open();
      await channel.say('green');
      await channel.sync();
      expect(await channel.sync(), isEmpty);
    });

    test('opened at a commit, it resumes there', () async {
      seated();
      final first = open();
      await first.say('raising the install gate');
      final resume = tree.tip();
      await first.say('green');
      final channel = open(cursor: resume);
      expect(channel.sync(), completion(hasLength(1)));
    });

    test('the cursor is never committed', () async {
      seated();
      final channel = open();
      await channel.say('green');
      bodies.calls.clear();
      await channel.sync();
      expect(bodies.calls, isEmpty);
    });

    test('an unborn channel has nothing to yield, and that is not an error',
        () async {
      tree.unborn();
      expect(await open().sync(), isEmpty);
    });
  });

  group('wait answers landed or expired, never content', () {
    test('nothing landing expires, bounded by within', () async {
      final result = await open().wait(within: const Duration(milliseconds: 50));
      expect(result, Arrival.expired);
    });

    test('a doorbell tick with a qualifying event landed', () async {
      seated();
      final channel = open();
      final pending = channel.wait();
      await channel.say('green');
      ticker.tick();
      expect(await pending, Arrival.landed);
    });

    test('landed leaves the cursor untouched — sync reads the whole batch '
        'afterwards, since wait carries no content of its own', () async {
      seated();
      final channel = open();
      final pending = channel.wait();
      await channel.say('green');
      ticker.tick();
      expect(await pending, Arrival.landed);
      final events = await channel.sync();
      expect(events.whereType<Spoke>().single.message.body, 'green');
    });

    test('a cursor opened at nothing sees a pre-existing message too, per '
        "sync's own contract, and wait still leaves the cursor untouched",
        () async {
      seated();
      final channel = open();
      await channel.say('before the wait ever opened');
      expect(
        await channel.wait(within: const Duration(milliseconds: 50)),
        Arrival.landed,
      );
      final events = await channel.sync();
      expect(events.whereType<Spoke>().single.message.body,
          'before the wait ever opened');
    });

    test('mentioning narrows what qualifies — an unrelated message never '
        'opens the window', () async {
      seated();
      final channel = open();
      final pending = channel.wait(
        mentioning: 'alfred',
        within: const Duration(milliseconds: 100),
      );
      await channel.say('just chatting');
      ticker.tick();
      // Nothing landed for @alfred, so the wall clock, not the tick, is what
      // ends this — proven by the bound elapsing rather than a race.
      expect(await pending, Arrival.expired);
    });

    test('naming the handle in mentioning opens the window', () async {
      seated();
      final channel = open();
      final pending = channel.wait(mentioning: 'alfred');
      await channel.say('@alfred status?');
      ticker.tick();
      expect(await pending, Arrival.landed);
    });

    test('the ticker is disposed once the wait ends', () async {
      await open().wait(within: const Duration(milliseconds: 20));
      expect(ticker.disposed, isTrue);
    });
  });

  group('every read answers at a point in history', () {
    /// A channel with a past: two utterances, a topic, and a second seat, each
    /// landing after the one before. The commit of each act is what a caller
    /// names to read the world as it then stood.
    late ChatAct spoke;
    late ChatAct topical;

    setUp(() async {
      seated();
      final channel = open();
      await channel.say('raising the install gate');
      spoke = tree.acts.last;
      await channel.setTopic('the install gate');
      topical = tree.acts.last;
      await channel.say('green');
      seated('cafe');
    });

    test('the transcript at a commit is what had landed by then', () async {
      expect(
        (await open().history(at: spoke.commit)).map((m) => m.body),
        ['raising the install gate'],
      );
      // And the present still answers with everything, so the claim is a
      // difference and not a reader that sees one message whatever it is asked.
      expect((await open().history()).map((m) => m.body),
          ['raising the install gate', 'green']);
    });

    test('the roster at a commit is who was there then', () async {
      expect(
        (await open().roster(at: spoke.commit)).participants.map(
              (p) => p.handle.local,
            ),
        ['alfred'],
      );
      expect(
        (await open().roster()).participants.map((p) => p.handle.local),
        ['alfred', 'cafe'],
      );
    });

    test('the topic at a commit is the one that stood then', () async {
      expect(await open().topic(at: spoke.commit), isNull);
      expect(await open().topic(at: topical.commit), 'the install gate');
    });

    // THE DISJOINT CLAIM for the reads: a reader that ignored `at` and answered
    // the present would satisfy every ordinary claim above except where the two
    // differ — and would also satisfy this one if it merely passed the argument
    // down without asking the tree for it.
    test('the tree is asked at that commit and not at the present', () async {
      tree.readsAt.clear();
      await open().topic(at: spoke.commit);
      expect(tree.readsAt, everyElement(spoke.commit));
    });

    test('a prefix is enough, because it is what a hand types', () async {
      expect(
        (await open().history(at: spoke.commit.substring(0, 3)))
            .map((m) => m.body),
        ['raising the install gate'],
      );
    });

    test('a commit this line does not carry is not the present', () async {
      expect(open().history(at: 'deadbee'), throwsA(isA<NoSuchCommit>()));
      expect(open().roster(at: 'deadbee'), throwsA(isA<NoSuchCommit>()));
      expect(open().topic(at: 'deadbee'), throwsA(isA<NoSuchCommit>()));
    });

    test('a prefix short of unique answers with the candidates', () async {
      // The doubles mint `c1000000`, `c2000000`, … so a bare `c` fits them all.
      expect(
        open().history(at: 'c'),
        throwsA(
          isA<AmbiguousCommit>().having(
            (e) => e.candidates.length,
            'candidates',
            greaterThan(1),
          ),
        ),
      );
    });
  });
}
