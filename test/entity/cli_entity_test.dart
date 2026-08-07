import 'dart:io';

import 'package:bentos_userland/entity.dart';
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

    test('a line that diverged is refused, and the ref does not move',
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
      expect(r.code, EntityRunner.refusedCode);
      expect(r.err, contains('diverged'));
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

    test('an instance the remote never carried is refused', () async {
      final far = await published();

      final r = await cli.run(['fetch', 't.chat:ghost', far.remote]);
      expect(r.code, EntityRunner.refusedCode);
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

        expect(second.code, EntityRunner.refusedCode);
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

          expect(r.code, EntityRunner.refusedCode);
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
          expect(second.code, EntityRunner.refusedCode);
          expect(second.code, isNot(255));
          expect(second.out, isEmpty);
        },
      );
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
