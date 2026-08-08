import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The plot's layout is the arming component's own and stays off the barrel, so
// the one place that names the hook path reaches it where it lives.
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The entity family of the coreutil: a thing brought into being or brought
/// here, interrogated, and given somewhere for its bytes to travel.
///
/// The suite drives the runner in process, over the fake port — the coreutil is
/// a client of the API and the API is already proven against real Git, so what
/// is asked here is the surface: which verb resolves what, what reaches stdout,
/// and which number the process leaves behind.
void main() {
  late Site site;
  late Cli cli;

  setUp(() {
    site = Site('cli');
    cli = Cli(site);
  });
  tearDown(() => site.dispose());

  group('the manifest', () {
    test('stands at entity.yaml, in the genesis tree', () {
      expect(Manifest.path, 'entity.yaml');
    });

    test('parses the declared name; blank when absent, never a throw', () {
      expect(Manifest.parse('name: t.declared\ntype: conversation\n').name,
          't.declared');
      expect(Manifest.parse('type: conversation\n').name, isEmpty);
      expect(Manifest.parse('').name, isEmpty);
    });
  });

  group('entity create', () {
    test('authors one here and prints its genesis', () async {
      final r = await cli.run(['create', 't.smoke']);

      expect(r.code, 0);
      expect(r.out.trim(), hasLength(40));
      expect(r.err, isEmpty);
    });

    test('registers with the place, so the name resolves from here', () async {
      await cli.run(['create', 't.smoke']);

      final r = await cli.run(['which', 't.smoke']);
      expect(r.code, 0);
      expect(r.out.trim(), site.root.path);
    });

    test('-C moves the vantage the authoring happens at', () async {
      final nested = site.nested('cto');

      final r = await cli.run(['-C', nested.path, 'create', 't.smoke']);
      expect(r.code, 0);

      expect((await cli.run(['which', 't.smoke'])).code, EntityRunner.notFoundCode);
      final there = await cli.run(['which', 't.smoke'], cwd: nested.path);
      expect(there.out.trim(), nested.path);
    });

    test('with no name, it is a usage fault', () async {
      final r = await cli.run(['create']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name>'));
    });
  });

  group('entity which', () {
    test('resolves upward — one installation serves everything below it',
        () async {
      final nested = site.nested('cto');
      await cli.run(['create', 't.smoke']);

      final r = await cli.run(['which', 't.smoke'], cwd: nested.path);
      expect(r.code, 0);
      expect(r.out.trim(), site.root.path);
    });

    test('nearest wins — an installation below shadows one above', () async {
      final nested = site.nested('cto');
      await cli.run(['create', 't.smoke']);
      await cli.run(['-C', nested.path, 'create', 't.smoke']);

      final below = await cli.run(['which', 't.smoke'], cwd: nested.path);
      expect(below.out.trim(), nested.path);

      final above = await cli.run(['which', 't.smoke']);
      expect(above.out.trim(), site.root.path);
    });

    test('an unresolved name reports both halves and exits not-found',
        () async {
      final r = await cli.run(['which', 't.absent']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('t.absent'));
      expect(r.err, contains(site.root.path));
      expect(r.out, isEmpty);
    });

    test('absence and a mistyped call are different answers', () async {
      // The presence test is the whole reason the verb exists: a script asks
      // *is this installed here?* and branches. One code for both questions
      // would leave it unable to ask either.
      final absent = await cli.run(['which', 't.absent']);
      final mistyped = await cli.run(['which']);

      expect(absent.code, EntityRunner.notFoundCode);
      expect(mistyped.code, EntityRunner.usageCode);
      expect(absent.code, isNot(mistyped.code));
    });
  });

  group('entity info', () {
    test('an entity that declares nothing still answers', () async {
      await cli.run(['create', 't.smoke']);

      final r = await cli.run(['info', 't.smoke']);
      expect(r.code, 0);
      expect(r.out, contains('name\tt.smoke'));
      expect(r.out, contains('genesis\t'));
      expect(r.err, contains('declares no manifest'));
    });

    test('prints the type, the actions, and the events they cross to', () async {
      await cli.run(['create', 't.chat']);
      _declare(site, 't.chat', 'type: conversation\nactions: [prompt, reply]\n');

      final r = await cli.run(['info', 't.chat']);
      expect(r.code, 0);
      expect(r.out, contains('type\tconversation'));
      expect(r.out, contains('action\tprompt'));
      expect(r.out, contains('action\treply'));
      for (final phase in ['attempted', 'landed', 'refused']) {
        expect(r.out, contains('event\tprompt.$phase'));
        expect(r.out, contains('event\treply.$phase'));
      }
      expect(r.err, isEmpty);
    });

    test('it lists actions and offers no way to perform one', () async {
      await cli.run(['create', 't.chat']);
      _declare(site, 't.chat', 'type: conversation\nactions: [prompt]\n');

      final r = await cli.run(['invoke', 't.chat', 'prompt']);
      expect(r.code, EntityRunner.usageCode);
    });

    test('is the document, one line per key, no key repeated', () async {
      // The law is "info prints this file". A manifest that declares every
      // field the type knows, `name` and `cardinality` included, is the one
      // fixture that can catch a field printed twice — once typed, once
      // through the raw dump — because the field-only assertions above never
      // looked at the output as a whole.
      await cli.run(['create', 't.chat']);
      _declare(
        site,
        't.chat',
        'name: t.chat\ntype: conversation\nactions: [prompt]\n'
            'cardinality: singular\n',
      );

      final r = await cli.run(['info', 't.chat']);
      expect(r.code, 0);
      // `action` and `event` are legitimately one line per vocabulary member,
      // so they repeat by design — every other key stands for one fact and
      // must appear exactly once.
      final keys = [
        for (final line in r.out.trim().split('\n'))
          if (!line.startsWith('action\t') && !line.startsWith('event\t'))
            line.split('\t').first,
      ];
      expect(keys.toSet().length, keys.length,
          reason: 'a repeated key means the document leaked twice: '
              'got $keys');
      expect(keys, containsAll(['name', 'genesis', 'type', 'cardinality']));
    });
  });

  group('entity publish and remotes', () {
    test('publish declares origin and moves the bytes there', () async {
      await cli.run(['create', 't.smoke']);
      final elsewhere = '${site.root.path}/away.git';
      site.run(() => ambientGit.init(elsewhere));

      final published = await cli.run(['publish', 't.smoke', elsewhere]);
      expect(published.code, 0);

      final r = await cli.run(['remotes', 't.smoke']);
      expect(r.out, contains('origin\t'));
    });

    test('remotes of a fresh entity is silence, not a failure', () async {
      await cli.run(['create', 't.smoke']);

      final r = await cli.run(['remotes', 't.smoke']);
      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('publish without a remote is a usage fault', () async {
      await cli.run(['create', 't.smoke']);

      final r = await cli.run(['publish', 't.smoke']);
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<remote>'));
    });
  });

  group('entity fetch', () {
    /// Two sites over one port, and a line taken at the far one — the shape
    /// federation actually has: A publishes to B, and the way back is `fetch`
    /// by the name publishing already declared.
    Future<({Site there, String remote, Action taken})> published() async {
      final origin = Site('origin');
      addTearDown(origin.dispose);
      final away = repositoryOf(origin.root.path, 't.chat');
      await Cli(origin, git: site.git).run(['create', 't.chat']);
      await Cli(origin, git: site.git).run(['new', 't.chat', 'c1']);

      await cli.run(['install', away, '--as', 't.chat']);
      final taken = await site.runAsync(() async {
        final result = await Entity('t.chat', from: origin.root.path)
            .instance('c1')
            .act('prompt', (w) {
          File('${w.directory.path}/1.txt').writeAsStringSync('over there');
        });
        return (result as Landed).action;
      });
      return (there: origin, remote: 'origin', taken: taken);
    }

    test('brings the line down and moves the ref here', () async {
      final far = await published();

      final r = await cli.run(['fetch', 't.chat:c1', far.remote]);
      expect(r.code, 0);
      expect(r.out.trim(), far.taken.commit.sha);
      expect((await cli.run(['tip', 't.chat:c1'])).out.trim(),
          far.taken.commit.sha);
      expect((await cli.run(['read', 't.chat:c1:1.txt'])).out, 'over there');
    });

    test('fetching twice is not a refusal', () async {
      final far = await published();

      await cli.run(['fetch', 't.chat:c1', far.remote]);
      final again = await cli.run(['fetch', 't.chat:c1', far.remote]);
      expect(again.code, 0);
      expect(again.out.trim(), far.taken.commit.sha);
    });

    test('a line that diverged says so, and the ref does not move',
        () async {
      final far = await published();
      await cli.run(['fetch', 't.chat:c1', far.remote]);
      // Both sides act on the same parent: two lines, legitimately.
      await site.runAsync(() async =>
          Entity('t.chat', from: far.there.root.path).instance('c1').act(
              'reply', (w) => File('${w.directory.path}/2.txt').writeAsStringSync('theirs')));
      final mine = await site.runAsync(() async {
        final result = await Entity('t.chat', from: site.root.path)
            .instance('c1')
            .act('reply', (w) {
          File('${w.directory.path}/3.txt').writeAsStringSync('mine');
        });
        return (result as Landed).action;
      });

      final r = await cli.run(['fetch', 't.chat:c1', far.remote]);
      // **The distinction survives the process boundary**, which is the whole
      // reason these are three numbers and not one. A script reading this must
      // be able to tell the terminating case from the non-terminating one: it
      // may loop on a contest, it must not loop on this, and it must not read
      // either as a gate having spoken.
      expect(r.code, EntityRunner.divergedCode);
      expect(r.code, isNot(EntityRunner.contestedCode));
      expect(r.code, isNot(EntityRunner.barredCode));
      expect(r.err, contains('diverged'));
      expect(r.err, contains(mine.commit.short),
          reason: 'the two tips are the whole of what divergence says');
      expect((await cli.run(['tip', 't.chat:c1'])).out.trim(), mine.commit.sha);
    });

    test('an undeclared remote is not found — never a raw URL', () async {
      final far = await published();
      final away = repositoryOf(far.there.root.path, 't.chat');

      final r = await cli.run(['fetch', 't.chat:c1', away]);
      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('declares no remote'));
      expect(r.out, isEmpty,
          reason: 'founding a relation sideways would make remotes lie');
    });

    test('an instance the remote never carried is not found', () async {
      final far = await published();

      final r = await cli.run(['fetch', 't.chat:ghost', far.remote]);
      // Moved from 3 to 1 on purpose. Grading this as a refusal was the report
      // answering the easy condition: nothing declined it and nothing raced it
      // — the thing named is simply not there, which is the same answer this
      // coreutil already gives for everything else it cannot find.
      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('no such instance'));
    });

    test('without a remote, it is a usage fault', () async {
      await cli.run(['create', 't.chat']);

      final r = await cli.run(['fetch', 't.chat:c1']);
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<remote>'));
    });
  });

  group('entity install', () {
    test('clones into this place, registers, and materializes nothing',
        () async {
      final origin = Site('origin');
      addTearDown(origin.dispose);
      // One port across both sites: a source is a URL, and the two sites share
      // a substrate the way two directories on one disk do.
      final source = repositoryOf(origin.root.path, 't.smoke');
      await Cli(origin, git: site.git).run(['create', 't.smoke']);

      final r = await cli.run(['install', source]);
      expect(r.code, 0);
      expect(r.out.trim(), 't.smoke');

      expect((await cli.run(['which', 't.smoke'])).out.trim(), site.root.path);
      expect(
        Directory('${site.root.path}/t.smoke').existsSync(),
        isFalse,
        reason: 'a site that only reacts holds no worktree at all',
      );
    });

    test('--as installs the same identity under another name', () async {
      final origin = Site('origin');
      addTearDown(origin.dispose);
      final source = repositoryOf(origin.root.path, 't.smoke');
      await Cli(origin, git: site.git).run(['create', 't.smoke']);

      final r = await cli.run(['install', source, '--as', 't.mine']);
      expect(r.code, 0);
      expect(r.out.trim(), 't.mine');
      expect((await cli.run(['which', 't.mine'])).code, 0);
      expect((await cli.run(['which', 't.smoke'])).code,
          EntityRunner.notFoundCode);
    });

    test('the manifest names the install when --as is silent', () async {
      final origin = Site('origin', site.git);
      addTearDown(origin.dispose);
      final source = repositoryOf(origin.root.path, 't.origin');
      await Cli(origin).run(['create', 't.origin']);
      _declare(origin, 't.origin', 'name: t.declared\n');

      final r = await cli.run(['install', source]);
      expect(r.code, 0);
      expect(r.out.trim(), 't.declared');
      expect((await cli.run(['which', 't.declared'])).code, 0);
    });

    test('--as overrides a name the manifest declares', () async {
      final origin = Site('origin', site.git);
      addTearDown(origin.dispose);
      final source = repositoryOf(origin.root.path, 't.origin');
      await Cli(origin).run(['create', 't.origin']);
      _declare(origin, 't.origin', 'name: t.declared\n');

      final r = await cli.run(['install', source, '--as', 't.mine']);
      expect(r.code, 0);
      expect(r.out.trim(), 't.mine');
      expect((await cli.run(['which', 't.declared'])).code,
          EntityRunner.notFoundCode);
    });

    test('a repository this system never authored installs, genesis and all',
        () async {
      // The disjoint witness: no create(), no genesis branch, no identity
      // trailer — an ordinary repository as any forge hands one out. Every
      // other fixture in this suite passes through Entity.create and cannot
      // tell a real clone from a mirror of itself; this one can.
      final origin = Site('origin', site.git);
      addTearDown(origin.dispose);
      final source = foreignRepository(
        site.git,
        origin.root.path,
        dirName: 't.foreign',
        declaredName: 't.imported',
      );

      final r = await cli.run(['install', source]);
      expect(r.code, 0);
      expect(r.out.trim(), 't.imported',
          reason: 'the manifest, never the source basename — the two differ '
              'here on purpose, so a name that matched by coincidence in '
              "every other fixture can't hide a precedence that never ran");

      final info = await cli.run(['info', 't.imported']);
      expect(info.code, 0);
      expect(info.out, contains('genesis\t'));
      expect(info.out, contains('type\tbentos.mem'));
    });

    test('a bare name is an invalid source, never something to discover',
        () async {
      // No scheme, no path separator: exactly the shape a discovery layer
      // would want to intercept. It must reach the port as a literal source
      // and fail there — never resolve to an installed entity.
      final r = await cli.run(['install', 't.mystery']);

      expect(r.code, isNot(0));
      expect(r.out, isEmpty,
          reason: 'a printed name here would mean the bare word was resolved '
              'rather than rejected as a source');
      expect((await cli.run(['which', 't.mystery'])).code,
          EntityRunner.notFoundCode);
    });

    group('a second install over what already stands', () {
      test('a registered name refuses — exit 3, and nothing touched',
          () async {
        final origin = Site('origin', site.git);
        addTearDown(origin.dispose);
        final source = repositoryOf(origin.root.path, 't.smoke');
        await Cli(origin).run(['create', 't.smoke']);

        final first = await cli.run(['install', source, '--as', 'dup']);
        expect(first.code, 0, reason: first.err);
        final before = (await cli.run(['listeners', 'dup'])).out;

        final second = await cli.run(['install', source, '--as', 'dup']);

        expect(second.code, EntityRunner.barredCode);
        expect(second.err, contains('dup'));
        expect(second.err, contains('already installed'));
        // Nothing cloned, registered or armed a second time: the same tables
        // read back exactly as the first install left them.
        expect((await cli.run(['listeners', 'dup'])).out, before);
      });

      test(
        'a directory standing with no registration refuses, and names the '
        'path rather than erasing it',
        () async {
          final origin = Site('origin', site.git);
          addTearDown(origin.dispose);
          final source = repositoryOf(origin.root.path, 't.smoke');
          await Cli(origin).run(['create', 't.smoke']);

          // A stranger, standing exactly where the install would land — made
          // by hand, never by this system's own clone.
          final standing =
              Directory(repositoryOf(site.root.path, 't.smoke')).parent.path;
          Directory(standing).createSync(recursive: true);
          File('$standing/left-by-somebody-else.txt')
              .writeAsStringSync('mine\n');

          final r = await cli.run(['install', source]);

          expect(r.code, EntityRunner.barredCode);
          expect(r.err, contains(standing));
          expect(
            File('$standing/left-by-somebody-else.txt').readAsStringSync(),
            'mine\n',
            reason: 'a refusal that names a directory does not clear it first',
          );
        },
      );

      test(
        'two installs at the same coordinate reproduce the refusal, never a '
        'raw substrate exception',
        () async {
          final origin = Site('origin', site.git);
          addTearDown(origin.dispose);
          final source = repositoryOf(origin.root.path, 't.smoke');
          await Cli(origin).run(['create', 't.smoke']);

          final first = await cli.run(['install', source, '--as', 'dup']);
          final second = await cli.run(['install', source, '--as', 'dup']);

          expect(first.code, 0, reason: first.err);
          // A named refusal a script can branch on — never the substrate's own
          // unhandled failure, which named no cure and no owner.
          expect(second.code, EntityRunner.barredCode);
          expect(second.code, isNot(255));
          expect(second.out, isEmpty);
        },
      );
    });
  });

  group('entity refit and entity upgrade', () {
    /// An installation in this place with an origin behind it, and a handle on
    /// that origin so a test can publish into it. Both sites share one port,
    /// the way two directories on one disk share a substrate.
    Future<({Site origin, String name})> installed() async {
      final origin = Site('origin', site.git);
      addTearDown(origin.dispose);
      await Cli(origin).run(['create', 't.thing']);
      final r = await cli.run(['install', repositoryOf(origin.root.path, 't.thing')]);
      expect(r.code, 0, reason: r.err);
      return (origin: origin, name: 't.thing');
    }

    /// Every red in this group must name the piece it wants, and an exit code
    /// compared against another number does not: `expected 1, actual 64` says
    /// nothing about the verb that is missing. This is asserted first, so the
    /// failure reads as *the surface does not carry this yet*.
    void onTheSurface(Run r) => expect(
          r.err,
          isNot(contains('Could not find a command')),
          reason: 'the verb is not registered on the coreutil yet',
        );

    /// Extends the origin's class line by one commit — somebody published.
    void publish(Site origin, String name, String document) =>
        _declare(origin, name, document);

    group('the surface', () {
      test('the two lines stand together, and refit says local, no network',
          () async {
        final usage = await cli.run([]);
        final text = usage.out.isEmpty ? usage.err : usage.out;

        expect(text, contains('refit'),
            reason: 'the verb is not registered on the coreutil yet');
        expect(text, contains('upgrade'));

        final refitLine = LineSplitter.split(text)
            .firstWhere((l) => l.trimLeft().startsWith('refit'),
                orElse: () => '');
        expect(
          refitLine.toLowerCase(),
          contains('no network'),
          reason: 'that word is the whole disambiguation between the two '
              'verbs, and it stands where the reader already is',
        );

        final lines = LineSplitter.split(text).toList();
        int at(String verb) =>
            lines.indexWhere((l) => l.trimLeft().startsWith(verb));
        expect(
          (at('upgrade') - at('refit')).abs(),
          1,
          reason: 'adjacent: a reader choosing between them must not have to '
              'find the second one somewhere else in the list',
        );
      });

      test('--dry-run is upgrade\'s alone', () async {
        await installed();
        final r = await cli.run(['refit', 't.thing', '--dry-run']);
        onTheSurface(r);
        expect(
          r.code,
          EntityRunner.usageCode,
          reason: 'refit moves nothing a reader would want to preview, so the '
              'flag is not quietly accepted and ignored',
        );
      });
    });

    group('refit at the boundary', () {
      test('an installation refits, locally, and says where the shim went',
          () async {
        await installed();
        final r = await cli.run(['refit', 't.thing']);
        onTheSurface(r);
        expect(r.code, 0, reason: r.err);
        expect(r.out, contains(ArmingTables.hookPath.split('/').last));
      });

      test('a name that resolves to nothing is not found — exit 1', () async {
        final r = await cli.run(['refit', 't.absent']);
        onTheSurface(r);
        expect(r.code, EntityRunner.notFoundCode);
        expect(r.code, isNot(EntityRunner.barredCode),
            reason: 'an absence must not wear a refusal\'s number');
      });

      test('a stage directory that is not ours is barred — exit 3, and the '
          'file survives', () async {
        await installed();
        final stage = Directory(
          p.join(p.dirname(repositoryOf(site.root.path, 't.thing')),
              Entity.classDirName),
        );
        if (stage.existsSync()) stage.deleteSync(recursive: true);
        stage.createSync(recursive: true);
        final stranger = File(p.join(stage.path, 'not-ours.txt'))
          ..writeAsStringSync('somebody else stood here');

        final r = await cli.run(['refit', 't.thing']);

        onTheSurface(r);
        expect(r.code, EntityRunner.barredCode);
        expect(r.code, isNot(EntityRunner.notFoundCode));
        expect(stranger.existsSync(), isTrue,
            reason: 'a refusal that names a directory does not clear it first');
      });
    });

    group('upgrade at the boundary', () {
      test('no origin is not found — exit 1, naming both cures', () async {
        await cli.run(['create', 't.mine']);

        final r = await cli.run(['upgrade', 't.mine']);

        onTheSurface(r);
        expect(r.code, EntityRunner.notFoundCode,
            reason: 'nothing was refused: the thing named is simply not there');
        expect(r.code, isNot(EntityRunner.barredCode));
        // **Asserted crossing the boundary, not in Dart.** A message that never
        // leaves the library has not reached the person it was written for, and
        // this one has to carry both roads out of the dead end.
        expect(r.err, contains('publish'));
        expect(r.err, contains('refit'));
      });

      test('a line that did not move exits 0 and names refit', () async {
        await installed();

        final r = await cli.run(['upgrade', 't.thing']);

        expect(r.code, 0, reason: r.err);
        expect(r.out.toLowerCase(), contains('refit'),
            reason: 'where nothing came down, the reader is told which verb '
                'does the local half without a network');
      });

      test('it reports the transition it performed and the lines that stand',
          () async {
        final at = await installed();
        final before = await cli.run(['info', at.name]);
        expect(before.code, 0);
        publish(at.origin, at.name, 'name: t.thing\ntype: bentos.mem\n');

        final r = await cli.run(['upgrade', at.name]);

        expect(r.code, 0, reason: r.err);
        final held = site.run(() =>
            Entity(at.name, from: site.root.path).genesis.short);
        expect(r.out, contains(held),
            reason: 'the sha reached is half of what a transition is');
      });

      test('a diverged line is exit 5, and it is not any of the others',
          () async {
        final at = await installed();
        // Two children of one parent: somebody published there, somebody
        // authored here. Neither line contains the other.
        publish(at.origin, at.name, 'name: t.thing\n# theirs\n');
        _declare(site, at.name, 'name: t.thing\n# ours\n');

        final r = await cli.run(['upgrade', at.name]);

        onTheSurface(r);
        expect(r.code, EntityRunner.divergedCode);
        expect(r.code, isNot(EntityRunner.contestedCode),
            reason: 'a script may loop on a contest and must not loop on this');
        expect(r.code, isNot(EntityRunner.barredCode),
            reason: 'and it must not read either as a gate having spoken');
        expect(r.err, contains('diverged'));
      });

      test('a contested swap is exit 4, and it is not exit 3', () async {
        final at = await installed();
        publish(at.origin, at.name, 'name: t.thing\n# theirs\n');

        // The lost swap, made genuine rather than simulated: a concurrent
        // actor lands its own write at the one seam where it really could —
        // after the fetch has returned, before this run's swap.
        final watched = WatchedGit(site.git);
        watched.afterFetch = () => _declare(site, at.name, 'name: t.thing\n'
            '# a concurrent actor, between the read and the swap\n');
        final watchedCli = Cli(site, git: watched);

        final r = await watchedCli.run(['upgrade', at.name]);

        onTheSurface(r);
        expect(r.code, EntityRunner.contestedCode);
        expect(r.code, isNot(EntityRunner.divergedCode),
            reason: 'a script may retry a contest and must not retry a '
                'divergence forever');
        expect(r.err, contains('contested'));
      });
    });
  });
}

/// Writes a manifest into an entity's genesis tree, at the port — the one thing
/// no verb of the coreutil does, because authoring a class's structure is the
/// author's business and not the platform's.
void _declare(Site site, String name, String document) {
  site.run(() {
    final gitDir = repositoryOf(site.root.path, name);
    final stage = Directory.systemTemp.createTempSync('declare-');
    File('${stage.path}/${Manifest.path}').writeAsStringSync(document);
    final genesis = ambientGit.revParse(gitDir, Entity.genesisRef)!;
    final sha = ambientGit.commitTree(
      gitDir,
      tree: ambientGit.writeTree(gitDir, workTree: stage.path),
      parents: [genesis.sha],
      message: 'declare\n',
    );
    ambientGit.updateRef(
      gitDir,
      ref: Entity.genesisRef,
      newCommit: Commit(sha),
      expected: genesis,
    );
    stage.deleteSync(recursive: true);
  });
}
