import 'dart:io';

import 'package:bentos_userland/entity.dart' hide Landed, Contested, Barred;
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/bank.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:bentos_userland/src/mem/writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// A [GistSource] that hands back a fixed line, and counts its own calls so a
/// test can prove the seam was — or was not — reached.
final class FixedGist implements GistSource {
  FixedGist(this._line);
  final String? _line;
  int calls = 0;

  @override
  Future<String?> derive(String body) async {
    calls++;
    return _line;
  }
}

/// A [GistSource] that fails the test if it is ever called — the fixture for
/// "the seam is never reached" claims.
final class UnreachableGist implements GistSource {
  @override
  Future<String?> derive(String body) async =>
      throw StateError('the seam must not be called here');
}

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  /// A freshly materialized `alfred.mem`, plus the raw [Entity] handle a test
  /// needs to land content [Writer] itself has no way to produce — malformed
  /// frontmatter, which no [Fields] value can express.
  ({Entity entity, Bank bank}) stand() {
    final entity = Entity('alfred.mem', from: site.root.path)..create(actor: testActor);
    entity.instance('main').create();
    final where = p.join(site.root.path, entity.name);
    entity.instance('main').materialize(at: where);
    final bank =
        (Bank.resolve('alfred.mem', vantage: site.root.path) as Found).bank;
    return (entity: entity, bank: bank);
  }

  group('remember', () {
    test('derives the gist through the seam and lands it', () async {
      await site.runAsync(() async {
        final s = stand();
        final gist = FixedGist('a derived cue');
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: gist);

        final outcome = await writer.remember(
          'domain/hello',
          type: MemType.semantic,
          attention: Attention(0.5),
          body: 'World.',
        );

        expect(outcome, isA<Written>());
        expect((outcome as Written).topics, ['domain/hello']);
        expect(gist.calls, 1);
        expect(s.bank.page('domain/hello')?.fields.gist, 'a derived cue');
      });
    });

    test('a manual gist skips the seam entirely', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer =
            Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: UnreachableGist());

        final outcome = await writer.remember(
          'domain/hello',
          type: MemType.semantic,
          attention: Attention(0.5),
          body: 'World.',
          gist: 'hand-written',
        );

        expect(outcome, isA<Written>());
        expect(s.bank.page('domain/hello')?.fields.gist, 'hand-written');
      });
    });

    test('no model and no manual gist refuses without landing', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'));

        final outcome = await writer.remember(
          'domain/hello',
          type: MemType.semantic,
          attention: Attention(0.5),
          body: 'World.',
        );

        expect(outcome, isA<RefusedWithoutModel>());
        expect((outcome as RefusedWithoutModel).topic, 'domain/hello');
        expect(s.bank.page('domain/hello'), isNull);
      });
    });

    test('a seam that derives nothing refuses the same as no seam at all',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer =
            Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist(null));

        final outcome = await writer.remember(
          'domain/hello',
          type: MemType.semantic,
          attention: Attention(0.5),
          body: 'World.',
        );

        expect(outcome, isA<RefusedWithoutModel>());
      });
    });

    test('created is stamped once and carried across a replace', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));

        await writer.remember('domain/hello',
            type: MemType.semantic, attention: Attention(0.5), body: 'v1');
        final firstCreated = s.bank.page('domain/hello')!.fields.created;
        expect(firstCreated, isNotNull);

        await writer.remember('domain/hello',
            type: MemType.semantic, attention: Attention(0.9), body: 'v2');
        final page = s.bank.page('domain/hello')!;

        expect(page.fields.created, firstCreated);
        expect(page.fields.attention, Attention(0.9));
        expect(page.body, 'v2');
      });
    });

    test('omitted tags replace with none, never inherited', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));

        await writer.remember('domain/hello',
            type: MemType.semantic,
            attention: Attention(0.5),
            body: 'v1',
            tags: ['first']);
        await writer.remember('domain/hello',
            type: MemType.semantic, attention: Attention(0.5), body: 'v2');

        expect(s.bank.page('domain/hello')!.fields.tags, isEmpty);
      });
    });
  });

  group('refocus', () {
    test('--to sets an absolute notch and leaves body and modified untouched',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body');
        final before = s.bank.page('a')!.fields.modified;

        final outcome =
            await writer.refocus(const Selector(topic: 'a'), to: Attention(0.9));

        expect(outcome, isA<Written>());
        final after = s.bank.page('a')!;
        expect(after.fields.attention, Attention(0.9));
        expect(after.body, 'body');
        expect(after.fields.modified, before);
      });
    });

    test('--by moves relative to the current notch, clamped to the scale',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.9), body: 'x');

        await writer.refocus(const Selector(topic: 'a'), byTenths: 3);

        expect(s.bank.page('a')!.fields.attention, Attention(1.0));
      });
    });

    test('a selector matching several pages lands one act over all of them',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'a');
        await writer.remember('b',
            type: MemType.semantic, attention: Attention(0.5), body: 'b');

        final outcome = await writer.refocus(
            Selector(minAttention: Attention(0.5)),
            to: Attention(0.8));

        expect(outcome, isA<Written>());
        expect((outcome as Written).topics.toSet(), {'a', 'b'});
        expect(s.bank.page('a')!.fields.attention, Attention(0.8));
        expect(s.bank.page('b')!.fields.attention, Attention(0.8));
      });
    });

    test('refuses a page whose frontmatter was itself guessed', () async {
      await site.runAsync(() async {
        final s = stand();
        final where = p.join(site.root.path, s.entity.name);
        File(p.join(where, 'broken.md'))
            .writeAsStringSync('---\nattention: 0.5\n---\nno type here\n');

        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'));
        final outcome =
            await writer.refocus(const Selector(topic: 'broken'), to: Attention(0.9));

        expect(outcome, isA<RefusedOnAssumedFields>());
        expect((outcome as RefusedOnAssumedFields).topic, 'broken');
        expect(outcome.assumptions, isNotEmpty);
      });
    });
  });

  group('regist', () {
    test('derives a fresh cue from the stored body, batched over a selector',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writing = FixedGist('old cue');
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: writing);
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body a');
        await writer.remember('b',
            type: MemType.semantic, attention: Attention(0.5), body: 'body b');

        final register = FixedGist('fresh cue');
        final regisWriter = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: register);
        final outcome = await regisWriter.regist(Selector(minAttention: Attention(0.5)));

        expect(outcome, isA<Written>());
        expect((outcome as Written).topics.toSet(), {'a', 'b'});
        expect(register.calls, 2);
        expect(s.bank.page('a')!.fields.gist, 'fresh cue');
        expect(s.bank.page('b')!.fields.gist, 'fresh cue');
        expect(s.bank.page('a')!.body, 'body a', reason: 'the body is never touched');
      });
    });

    test('--set skips the seam entirely', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('old'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'x');

        final setter = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: UnreachableGist());
        final outcome =
            await setter.regist(const Selector(topic: 'a'), set: 'hand-set');

        expect(outcome, isA<Written>());
        expect(s.bank.page('a')!.fields.gist, 'hand-set');
      });
    });

    test('no model and no --set refuses without landing', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('old'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'x');
        final before = s.bank.page('a')!.fields.gist;

        final modelless = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'));
        final outcome = await modelless.regist(const Selector(topic: 'a'));

        expect(outcome, isA<RefusedWithoutModel>());
        expect(s.bank.page('a')!.fields.gist, before);
      });
    });

    test('refuses a hand-edited page rather than describe a version nobody is reading',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('old'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'committed');
        final where = p.join(site.root.path, s.entity.name);
        File(p.join(where, 'a.md')).writeAsStringSync('mine, not landed');

        final outcome = await writer.regist(const Selector(topic: 'a'));

        expect(outcome, isA<RefusedOnHandEdit>());
        expect((outcome as RefusedOnHandEdit).topics, ['a']);
        expect(File(p.join(where, 'a.md')).readAsStringSync(), 'mine, not landed');
      });
    });

    test('refuses a page whose frontmatter was itself guessed, even clean',
        () async {
      await site.runAsync(() async {
        final s = stand();
        await s.entity.instance('main').act(
          'page',
          (area) => File(p.join(area.directory.path, 'broken.md'))
              .writeAsStringSync('---\nattention: 0.5\n---\nno type here\n'),
          actor: Actor('seed', email: 'seed@test.local'),
        );
        s.bank.advance();
        expect(s.bank.handEdited, isEmpty, reason: 'landed and advanced — the tree is clean');

        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        final outcome = await writer.regist(const Selector(topic: 'broken'));

        expect(outcome, isA<RefusedOnAssumedFields>());
        expect((outcome as RefusedOnAssumedFields).topic, 'broken');
      });
    });
  });

  group('tag', () {
    test('--add appends and leaves body and modified untouched', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body', tags: ['old']);
        final before = s.bank.page('a')!.fields.modified;

        final outcome = await writer.tag(const Selector(topic: 'a'), add: ['fresh']);

        expect(outcome, isA<Written>());
        final after = s.bank.page('a')!;
        expect(after.fields.tags, ['old', 'fresh']);
        expect(after.body, 'body');
        expect(after.fields.modified, before);
      });
    });

    test('--remove drops a tag', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body', tags: ['old', 'keep']);

        await writer.tag(const Selector(topic: 'a'), remove: ['old']);

        expect(s.bank.page('a')!.fields.tags, ['keep']);
      });
    });

    test('adding a tag already present is a no-op, not a duplicate', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body', tags: ['old']);

        await writer.tag(const Selector(topic: 'a'), add: ['old']);

        expect(s.bank.page('a')!.fields.tags, ['old']);
      });
    });

    test('removing a tag already absent is a no-op, not an error', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'body', tags: ['old']);

        final outcome = await writer.tag(const Selector(topic: 'a'), remove: ['never-there']);

        expect(outcome, isA<Written>());
        expect(s.bank.page('a')!.fields.tags, ['old']);
      });
    });

    test('a selector matching several pages lands one act over all of them', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'a');
        await writer.remember('b',
            type: MemType.semantic, attention: Attention(0.5), body: 'b');

        final outcome = await writer.tag(
            Selector(minAttention: Attention(0.5)), add: ['batched']);

        expect(outcome, isA<Written>());
        expect((outcome as Written).topics.toSet(), {'a', 'b'});
        expect(s.bank.page('a')!.fields.tags, ['batched']);
        expect(s.bank.page('b')!.fields.tags, ['batched']);
      });
    });

    test('refuses a page whose frontmatter was itself guessed', () async {
      await site.runAsync(() async {
        final s = stand();
        final where = p.join(site.root.path, s.entity.name);
        File(p.join(where, 'broken.md'))
            .writeAsStringSync('---\nattention: 0.5\n---\nno type here\n');

        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'));
        final outcome =
            await writer.tag(const Selector(topic: 'broken'), add: ['x']);

        expect(outcome, isA<RefusedOnAssumedFields>());
        expect((outcome as RefusedOnAssumedFields).topic, 'broken');
      });
    });
  });

  group('forget', () {
    test('removes a page by topic', () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'x');

        final outcome = await writer.forget('a');

        expect(outcome, isA<Written>());
        expect((outcome as Written).topics, ['a']);
        s.bank.advance();
        expect(s.bank.page('a'), isNull);
      });
    });
  });

  group('a gate refusing', () {
    test('is reported as RefusedByGate, and the same act would refuse again',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final writer = Writer(s.bank, actor: Actor('tester', email: 'tester@test.local'), gist: FixedGist('cue'));
        site.git.declineNextSwap = 'entity: refused by r4: bin/check\ncheck: illegal';

        final outcome = await writer.remember('a',
            type: MemType.semantic, attention: Attention(0.5), body: 'x');

        expect(outcome, isA<RefusedByGate>());
        expect((outcome as RefusedByGate).reason, contains('illegal'));
        expect(s.bank.page('a'), isNull);
      });
    });
  });

  group('a contested tip', () {
    test('exhausting the attempts refuses, and nothing of that act lands',
        () async {
      await site.runAsync(() async {
        final s = stand();
        final one = Writer(s.bank, actor: Actor('one', email: 'one@test.local'), gist: FixedGist('cue'), attempts: 1);
        final two = Writer(s.bank, actor: Actor('two', email: 'two@test.local'), gist: FixedGist('cue'), attempts: 1);

        final results = await Future.wait([
          one.remember('a', type: MemType.semantic, attention: Attention(0.5), body: '1'),
          two.remember('b', type: MemType.semantic, attention: Attention(0.5), body: '2'),
        ]);

        expect(results, anyElement(isA<Written>()));
        expect(results, anyElement(isA<RefusedAsContested>()));
        final refused =
            results.firstWhere((o) => o is RefusedAsContested) as RefusedAsContested;
        expect(refused.attempts, 1);
      });
    });

    test('is absorbed by a retry, landing on the second attempt', () async {
      await site.runAsync(() async {
        final s = stand();
        final one = Writer(s.bank, actor: Actor('one', email: 'one@test.local'), gist: FixedGist('cue'));
        final two = Writer(s.bank, actor: Actor('two', email: 'two@test.local'), gist: FixedGist('cue'));

        final results = await Future.wait([
          one.remember('a', type: MemType.semantic, attention: Attention(0.5), body: '1'),
          two.remember('b', type: MemType.semantic, attention: Attention(0.5), body: '2'),
        ]);

        expect(results, everyElement(isA<Written>()));
        s.bank.advance();
        expect(s.bank.page('a'), isNotNull);
        expect(s.bank.page('b'), isNotNull);
      });
    });
  });
}
