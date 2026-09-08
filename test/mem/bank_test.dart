import 'dart:io';

import 'package:bentos_userland/src/git/model/actor.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/bank.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';
import 'stand.dart';

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  Page page(String topic, String body) => Page(
        topic: topic,
        fields: Fields(type: MemType.semantic, attention: Attention(0.5)),
        body: body,
      );

  group('resolve', () {
    test('a name with no installation is NotFound, carrying the vantage', () {
      final resolution =
          site.run(() => Bank.resolve('nobody.mem', vantage: site.root.path));
      expect(resolution, isA<NotFound>());
      final notFound = resolution as NotFound;
      expect(notFound.tried, ['nobody.mem']);
      expect(notFound.vantage, site.root.path);
    });

    test('a bare name resolves the .mem tree beside it', () {
      site.run(() => standBank(site, 'alfred.mem'));
      final resolution =
          site.run(() => Bank.resolve('alfred', vantage: site.root.path));
      expect(resolution, isA<Found>());
      expect((resolution as Found).bank.name, 'alfred.mem');
    });

    test('a tree named exactly as asked wins over the suffixed one', () {
      site.run(() {
        standBank(site, 'alfred');
        standBank(site, 'alfred.mem');
      });
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
      site.run(() => standBank(site, 'alfred.mem'));
      final resolution =
          site.run(() => Bank.resolve('alfred.mem', vantage: site.root.path));
      expect(resolution, isA<Found>());
      final bank = (resolution as Found).bank;
      expect(bank.name, 'alfred.mem');
      expect(bank.vantage, site.root.path);
    });

    test('resolves from a vantage nested below the installation', () {
      final deep = site.nested('workshop');
      site.run(() => standBank(site, 'alfred.mem'));
      final resolution =
          site.run(() => Bank.resolve('alfred.mem', vantage: deep.path));
      expect(resolution, isA<Found>());
    });

    test('a gitlink with no checkout is Found and has no tree', () {
      site.run(() => standGitlinkOnly(site, 'alfred.mem'));
      final bank = site.run(() => resolved(site, 'alfred.mem'));
      expect(bank.hasTree, isFalse);
      expect(bank.pages(), isEmpty);
    });
  });

  group('pages and page — read in place', () {
    test('a bank never checked out has no pages, and no page by name', () {
      site.run(() => standGitlinkOnly(site, 'alfred.mem'));
      final bank = site.run(() => resolved(site, 'alfred.mem'));
      expect(bank.pages(), isEmpty);
      expect(bank.page('anything'), isNull);
    });

    test('reads pages back from the working tree after a land and an advance',
        () async {
      await site.runAsync(() async {
        standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');

        final landing = await bank.land(
          'page',
          (draft) => draft.write(page('domain/hello', 'World.')),
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
        standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');
        expect(bank.handEdited, isEmpty);
      });
    });

    test('a hand-edited page is named by topic, non-markdown noise dropped',
        () async {
      await site.runAsync(() async {
        final where = standBank(site, 'alfred.mem');
        File(p.join(where.path, 'stray.md')).writeAsStringSync('nobody wrote this');
        File(p.join(where.path, 'notes.txt')).writeAsStringSync('not a page');
        final bank = resolved(site, 'alfred.mem');
        expect(bank.handEdited, ['stray']);
      });
    });
  });

  group('advance', () {
    test('a bank with no tree at the uniform address is NoTree, never Advanced',
        () {
      site.run(() => standGitlinkOnly(site, 'alfred.mem'));
      final bank = site.run(() => resolved(site, 'alfred.mem'));
      final advance = site.run(() => bank.advance());
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
        final where = standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');
        await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        expect(site.git.currentBranch(where.path), 'main');

        final first = bank.advance();
        expect(first, isA<Advanced>());
        expect(File(p.join(where.path, 'a.md')).existsSync(), isTrue);

        expect(bank.advance(), isA<Advanced>());
      });
    });

    test('a clean tree behind the line is fast-forwarded, and reports Advanced',
        () async {
      await site.runAsync(() async {
        final where = standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');
        await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        expect(bank.advance(), isA<Advanced>());
        expect(File(p.join(where.path, 'a.md')).existsSync(), isTrue);
      });
    });

    test('a dirty tree refuses the next land outright, naming what blocks it',
        () async {
      await site.runAsync(() async {
        final where = standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');
        await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(bank.advance(), isA<Advanced>());

        File(p.join(where.path, 'a.md')).writeAsStringSync('mine, not yours');
        Object? thrown;
        try {
          await bank.land(
            'page',
            (draft) => draft.write(page('b', 'y')),
            actor: Actor('tester', email: 'tester@test.local'),
          );
        } catch (e) {
          thrown = e;
        }
        expect(thrown, isA<TreeCarriesWork>());
        expect((thrown as TreeCarriesWork).paths, contains('a.md'));
        expect(
          File(p.join(where.path, 'a.md')).readAsStringSync(),
          'mine, not yours',
        );
        expect(File(p.join(where.path, 'b.md')).existsSync(), isFalse);
      });
    });

    test(
        'a hand-dirtied tree declines advance() alone — Behind, naming what '
        'blocks it, with no land() ever attempted', () async {
      await site.runAsync(() async {
        final where = standBank(site, 'alfred.mem');
        final bank = resolved(site, 'alfred.mem');
        await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(bank.advance(), isA<Advanced>());

        File(p.join(where.path, 'a.md')).writeAsStringSync('mine, not yours');

        final advance = bank.advance();
        expect(advance, isA<Behind>());
        expect((advance as Behind).blocking, contains('a.md'));
        expect(advance.report, contains('uncommitted work'));
        expect(
          File(p.join(where.path, 'a.md')).readAsStringSync(),
          'mine, not yours',
        );
      });
    });

    test(
        'a detached bank tree: land() is Barred, and advance() on a dirty '
        'detached tree reports Behind', () async {
      await site.runAsync(() async {
        final where = standBank(site, 'alfred.mem');
        final detach =
            Process.runSync('git', ['-C', where.path, 'checkout', '--detach']);
        expect(detach.exitCode, 0);

        File(p.join(where.path, 'a.md')).writeAsStringSync('stale local content');

        final bank = resolved(site, 'alfred.mem');

        final landing = await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );
        expect(landing, isA<Barred>());

        expect(
          File(p.join(where.path, 'a.md')).readAsStringSync(),
          'stale local content',
        );

        final advance = bank.advance();
        expect(advance, isA<Behind>());
        expect((advance as Behind).blocking, contains('a.md'));
      });
    });
  });

  group('land', () {
    test('a bank whose line was never born is Barred, not a stack trace',
        () async {
      await site.runAsync(() async {
        standBank(site, 'alfred.mem', born: false);
        final bank = resolved(site, 'alfred.mem');

        final landing = await bank.land(
          'page',
          (draft) => draft.write(page('a', 'x')),
          actor: Actor('tester', email: 'tester@test.local'),
        );

        expect(landing, isA<Barred>());
        expect((landing as Barred).reason, contains('never born'));
      });
    });
  });
}
