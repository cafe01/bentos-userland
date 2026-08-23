import 'dart:io';

import 'package:bentos_userland/entity.dart' hide Landed, Contested, Barred;
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/bank.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  group('resolve', () {
    test('a name with no installation is NotFound, carrying the vantage', () {
      final resolution =
          site.run(() => Bank.resolve('nobody.mem', vantage: site.root.path));
      expect(resolution, isA<NotFound>());
      final notFound = resolution as NotFound;
      expect(notFound.tried, ['nobody.mem']);
      expect(notFound.vantage, site.root.path);
    });

    test('a bare name resolves the .mem entity beside it', () {
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final resolution =
          site.run(() => Bank.resolve('alfred', vantage: site.root.path));
      expect(resolution, isA<Found>());
      expect((resolution as Found).bank.name, 'alfred.mem');
    });

    test('an entity named exactly as asked wins over the suffixed one', () {
      site.run(() => Entity('alfred', from: site.root.path).create(actor: testActor));
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final resolution =
          site.run(() => Bank.resolve('alfred', vantage: site.root.path));
      expect((resolution as Found).bank.name, 'alfred');
    });

    test('a bare miss reports both names it tried, in order', () {
      final resolution =
          site.run(() => Bank.resolve('nobody', vantage: site.root.path));
      expect((resolution as NotFound).tried, ['nobody', 'nobody.mem']);
    });

    test('an installed name is Found, and carries its own vantage', () {
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final resolution =
          site.run(() => Bank.resolve('alfred.mem', vantage: site.root.path));
      expect(resolution, isA<Found>());
      final bank = (resolution as Found).bank;
      expect(bank.name, 'alfred.mem');
      expect(bank.vantage, site.root.path);
    });

    test('resolves from a vantage nested below the installation', () {
      final deep = site.nested('workshop');
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final resolution =
          site.run(() => Bank.resolve('alfred.mem', vantage: deep.path));
      expect(resolution, isA<Found>());
    });
  });

  group('pages and page — read in place', () {
    test('a bank never materialized has no pages, and no page by name', () {
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final bank =
          (site.run(() => Bank.resolve('alfred.mem', vantage: site.root.path))
                  as Found)
              .bank;
      expect(bank.pages(), isEmpty);
      expect(bank.page('anything'), isNull);
    });

    test('reads pages back from the working tree after a land and an advance',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;

        final landing = await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'domain/hello',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'World.',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(landing, isA<Landed>());

        final advance = bank.advance();
        expect(advance, isA<Advanced>());

        final pages = bank.pages();
        expect(pages.map((pg) => pg.topic), ['domain/hello']);
        expect(bank.page('domain/hello')?.body, 'World.');
        expect(bank.page('nope'), isNull);
      });
    });
  });

  group('handEdited', () {
    test('an untouched tree reports no hand-edits', () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        expect(bank.handEdited, isEmpty);
      });
    });

    test('a hand-edited page is named by topic, non-markdown noise dropped',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        File(p.join(where, 'stray.md')).writeAsStringSync('nobody wrote this');
        File(p.join(where, 'notes.txt')).writeAsStringSync('not a page');

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        expect(bank.handEdited, ['stray.md'.replaceAll('.md', '')]);
      });
    });
  });

  group('advance', () {
    test('a bank with no tree at the uniform address is NoTree, never Advanced',
        () {
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final bank =
          (site.run(() => Bank.resolve('alfred.mem', vantage: site.root.path))
                  as Found)
              .bank;
      final advance = site.run(() => bank.advance());
      // Not Advanced. "Nothing is materialized" and "the tree is current" are
      // opposite facts, and this returned success for the first until a write
      // that landed nowhere anybody could read reported as a clean write.
      expect(advance, isA<NoTree>());
      expect(
        (advance as NoTree).address.path,
        p.join(site.root.path, 'alfred.mem'),
      );
    });

    test(
        'an attached tree already stands at its tip — Advanced, not Behind, '
        'because an act commits there and moves the ref by doing so',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        // The act committed in this tree, so it is attached and already
        // stands at the branch's tip — the ordinary condition of an instance
        // now, not a trap. A guard once refused every attached tree on the
        // belief that attached meant "detached by hand behind the ref"; that
        // belief is false once an act commits where the tree stands.
        expect(site.git.currentBranch(where), 'main');

        // Loud, not silent: there is genuinely nothing to do, and the report
        // says so rather than passing over it — the case `entity refresh`'s
        // own caller relies on to tell "nothing moved" from "already home".
        final first = bank.advance();
        expect(first, isA<Advanced>());
        expect(File(p.join(where, 'a.md')).existsSync(), isTrue);

        // Every time, not once: a clean attached tree answers the same way
        // on every call, because the condition is a property of the tree.
        expect(bank.advance(), isA<Advanced>());
      });
    });

    test('a clean tree behind the line is fast-forwarded, and reports Advanced',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        expect(bank.advance(), isA<Advanced>());
        expect(File(p.join(where, 'a.md')).existsSync(), isTrue);
      });
    });

    test('a dirty tree refuses the next land outright, naming what blocks it',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        // A first page lands and is committed into the tree, so its file is
        // now tracked at the commit the tree stands at.
        await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(bank.advance(), isA<Advanced>());

        // The person edits the tracked file by hand. An act commits in this
        // very tree now, so the guard fires before the second land's body
        // ever runs — there is no private area left for it to land into
        // unseen, and no later `advance()` call to decline instead.
        File(p.join(where, 'a.md')).writeAsStringSync('mine, not yours');
        Object? thrown;
        try {
          await bank.land(
            'page',
            (draft) => draft.write(Page(
              topic: 'b',
              fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
              body: 'y',
            )),
            actor: Actor('tester', email: 'tester@test.local'),
          );
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<TreeCarriesWork>());
        expect((thrown as TreeCarriesWork).paths, contains('a.md'));
        // Never discarded: the person's edit is still exactly there.
        expect(File(p.join(where, 'a.md')).readAsStringSync(), 'mine, not yours');
        // And the landed page never silently arrived either — nothing was
        // moved, exactly as the contract promises.
        expect(File(p.join(where, 'b.md')).existsSync(), isFalse);
      });
    });

    test(
        'a hand-dirtied tree declines advance() alone — Behind, naming what '
        'blocks it, with no land() ever attempted', () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(bank.advance(), isA<Advanced>());

        // The person edits the tracked file by hand, and nothing calls
        // `land()` afterward — `advance()` is asked directly, on its own,
        // the one route into `Behind` that bank.dart:168 still returns.
        File(p.join(where, 'a.md')).writeAsStringSync('mine, not yours');

        final advance = bank.advance();
        expect(advance, isA<Behind>());
        expect((advance as Behind).blocking, contains('a.md'));
        expect(advance.report, contains('uncommitted work'));
        // Never discarded, never overwritten: declining is the whole act.
        expect(
          File(p.join(where, 'a.md')).readAsStringSync(),
          'mine, not yours',
        );
      });
    });

    test(
        'a legacy-detached bank tree: land() stands a SECOND attached tree '
        'elsewhere, and advance() on the original reports Behind', () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        // The legacy condition: a tree of ours stands at the bank's own
        // materialization address, but detached — following no branch.
        // `standingAt` asks the substrate for an *attached* worktree of
        // 'main' only, so a detached tree here is invisible to it.
        final detach =
            Process.runSync('git', ['-C', where, 'checkout', '--detach']);
        expect(detach.exitCode, 0);

        // Untracked, and colliding with the very file the coming write
        // introduces — the shape that makes Git's own checkout decline
        // rather than silently fast-forward the stale tree underneath it.
        File(p.join(where, 'a.md')).writeAsStringSync('stale local content');

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;

        // `land()` finds no attached tree, so it materializes a second one
        // at the instance's own convention address and commits there — the
        // branch moves under a tree nobody asked to read from.
        final landing = await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(landing, isA<Landed>());

        // The original tree at the bank's own address never received the
        // write — the second tree did — and it is still detached.
        expect(
          File(p.join(where, 'a.md')).readAsStringSync(),
          'stale local content',
        );

        // advance() reads at the bank's own address — the original,
        // detached tree — and tries to catch it up. Git's own checkout
        // declines because the untracked local file would be overwritten,
        // and that decline is exactly what Behind carries outward: real,
        // not merely theoretical, on this route.
        final advance = bank.advance();
        expect(advance, isA<Behind>());
        expect((advance as Behind).blocking, contains('a.md'));
        expect(advance.report, contains('would be overwritten'));
      });
    });
  });

  group('land', () {
    test('a bank whose line was never born is Barred, not a stack trace',
        () async {
      await site.runAsync(() async {
        // Created, never given its instance — an ordinary condition of the
        // world, which the floor answers by throwing.
        Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;

        final landing = await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'x',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        expect(landing, isA<Barred>());
        expect((landing as Barred).reason, contains('never born'));
      });
    });
  });
}
