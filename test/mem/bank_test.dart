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
    test('a bank never materialized has nothing to advance', () {
      site.run(() => Entity('alfred.mem', from: site.root.path).create(actor: testActor));
      final bank =
          (site.run(() => Bank.resolve('alfred.mem', vantage: site.root.path))
                  as Found)
              .bank;
      expect(bank.advance(), isA<Advanced>());
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

    test('a dirty tree behind the line declines, and names what blocks it',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();
        final where = p.join(site.root.path, entity.name);
        entity.instance('main').materialize(at: where);

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;
        // A first page lands and is fast-forwarded into the tree, so its
        // file is now tracked at the commit the tree stands at.
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

        // The person edits the tracked file by hand, and a second page
        // lands — moving the ref beyond what the dirty tree stands at.
        File(p.join(where, 'a.md')).writeAsStringSync('mine, not yours');
        await bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'b',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: 'y',
          )),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        final advance = bank.advance();
        expect(advance, isA<Behind>());
        expect((advance as Behind).blocking, contains('a.md'));
        // Never discarded: the person's edit is still exactly there.
        expect(File(p.join(where, 'a.md')).readAsStringSync(), 'mine, not yours');
        // And the landed page never silently arrived either — nothing was
        // moved, exactly as the contract promises.
        expect(File(p.join(where, 'b.md')).existsSync(), isFalse);
      });
    });
  });

  group('land', () {
    test('two acts against one tip: one lands, the other is Contested',
        () async {
      await site.runAsync(() async {
        final entity = Entity('alfred.mem', from: site.root.path).create(actor: testActor);
        entity.instance('main').create();

        final bank =
            (Bank.resolve('alfred.mem', vantage: site.root.path) as Found)
                .bank;

        final first = bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'a',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: '1',
          )),
          actor: Actor('one', email: 'one@test.local'),
        );
        final second = bank.land(
          'page',
          (draft) => draft.write(Page(
            topic: 'b',
            fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
            body: '2',
          )),
          actor: Actor('two', email: 'two@test.local'),
        );

        final results = await Future.wait([first, second]);
        expect(results, anyElement(isA<Landed>()));
        expect(results, anyElement(isA<Contested>()));
      });
    });
  });
}
