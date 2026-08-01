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
