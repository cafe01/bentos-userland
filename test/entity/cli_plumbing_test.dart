import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The plumbing family of the coreutil — the family that matters most, because
/// the callers here are programs: three separate processes taking one act, and
/// the compare-and-swap carried between them by hand.
void main() {
  late Site site;
  late Cli cli;

  setUp(() async {
    site = Site('cli');
    cli = Cli(site);
    await cli.run(['create', 't.chat', ...Cli.signed]);
    await cli.run(['new', 't.chat', 'c1']);
  });
  tearDown(() => site.dispose());

  /// The pair `work` hands back: an area, and the value the swap will demand.
  Future<({String area, String parent})> work(String coord) async {
    final r = await cli.run(['work', coord]);
    expect(r.code, 0, reason: r.err);
    final parts = r.out.trim().split('\t');
    return (area: parts[0], parent: parts[1]);
  }

  group('entity tip and resolve', () {
    test('tip is the value an actor hands back to the swap', () async {
      final tip = await cli.run(['tip', 't.chat:c1']);

      expect(tip.code, 0);
      expect(tip.out.trim(), hasLength(40));
      expect((await work('t.chat:c1')).parent, tip.out.trim());
    });

    test('an instance that was never born has no tip', () async {
      final r = await cli.run(['tip', 't.chat:ghost']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.out, isEmpty);
    });

    test('resolve turns the selection into somewhere to stand', () async {
      final r = await cli.run(['resolve', 't.chat:c1']);

      expect(r.code, 0);
      expect(r.out.trim(), '${site.root.path}/t.chat');
    });
  });

  group('entity path', () {
    test('is the escape hatch, and it names a real repository', () async {
      final r = await cli.run(['path', 't.chat']);

      expect(r.code, 0);
      expect(r.out.trim(), repositoryOf(site.root.path, 't.chat'));
    });

    test('of an entity nobody installed here, not found', () async {
      final r = await cli.run(['path', 't.absent']);

      expect(r.code, EntityRunner.notFoundCode);
    });
  });

  group('work, commit and release', () {
    test('three processes take one act', () async {
      final opened = await work('t.chat:c1');
      File('${opened.area}/1.txt').writeAsStringSync('hello');

      final landed = await cli.run([
        'commit', 't.chat:c1', 'prompt',
        '-w', opened.area, '--parent', opened.parent, '--actor', 'alfred', '--actor-email', 'alfred@test.local',
      ]);
      expect(landed.code, 0, reason: landed.err);
      expect(landed.out.trim(), hasLength(40));

      expect((await cli.run(['read', 't.chat:c1:1.txt'])).out, 'hello');
      expect((await cli.run(['log', 't.chat:c1'])).out,
          contains('\tprompt\talfred\t'));

      final released = await cli.run(['release', opened.area]);
      expect(released.code, 0);
      expect(Directory(opened.area).existsSync(), isFalse);
    });

    test('the plumbing says the sentence too — a program is a caller here',
        () async {
      // The family that matters most: the callers are programs, and an actor
      // whose write does not fit the bracket must still be able to say what it
      // did. Without this the sentence is a porcelain-only fact.
      final opened = await work('t.chat:c1');
      File('${opened.area}/1.txt').writeAsStringSync('hello');

      await cli.run([
        'commit', 't.chat:c1', 'prompt',
        '-w', opened.area, '--parent', opened.parent, '--actor', 'cafe', '--actor-email', 'cafe@test.local',
        '--say', 'user say',
      ]);

      expect((await cli.run(['log', 't.chat:c1'])).out.trim().split('\t').last,
          'user say');
      await cli.run(['release', opened.area]);
    });

    test('a stale parent is contested, and a contest is not an error', () async {
      // Two actors read the same tip. The first lands; the second is holding a
      // value the ref no longer has, and the substrate refuses it under lock.
      final first = await work('t.chat:c1');
      final second = await work('t.chat:c1');
      expect(first.parent, second.parent);

      File('${first.area}/1.txt').writeAsStringSync('mine');
      final landed = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '-w', first.area, '--parent', first.parent, ...Cli.signed],
      );
      expect(landed.code, 0);

      File('${second.area}/1.txt').writeAsStringSync('theirs');
      final refused = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '-w', second.area, '--parent', second.parent, ...Cli.signed],
      );

      // Contested: the ref moved under the second actor and no gate was asked,
      // so the code invites the retry that will terminate.
      expect(refused.code, EntityRunner.contestedCode);
      expect(refused.err, contains('contested'));
      expect(refused.out, isEmpty);
      expect((await cli.run(['read', 't.chat:c1:1.txt'])).out, 'mine');
      expect((await cli.run(['log', 't.chat:c1'])).out.trim().split('\n'),
          hasLength(1));
    });

    test('each act gets an area of its own', () async {
      final first = await work('t.chat:c1');
      final second = await work('t.chat:c1');

      expect(first.area, isNot(second.area));
    });

    test('release is idempotent, and a path nobody opened is not a fault',
        () async {
      final opened = await work('t.chat:c1');

      expect((await cli.run(['release', opened.area])).code, 0);
      expect((await cli.run(['release', opened.area])).code, 0);
      expect((await cli.run(['release', '${site.root.path}/nowhere'])).code, 0);
    });

    test('release deregisters a materialization too', () async {
      final where = '${site.root.path}/face';
      await cli.run(['materialize', 't.chat:c1', '--at', where]);

      expect((await cli.run(['release', where])).code, 0);
      expect(Directory(where).existsSync(), isFalse);
    });

    test('commit without a parent is a usage fault', () async {
      final opened = await work('t.chat:c1');

      final r = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '-w', opened.area, ...Cli.signed],
      );
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('--parent'));
    });

    test('commit without an area is a usage fault', () async {
      final r = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '--parent', 'deadbeef', ...Cli.signed],
      );

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('-w'));
    });
  });

  group('entity emit — the plumbing that calls into it', () {
    // Behaviour — a real transaction driving a real dispatch call — is proven
    // against the substrate in `subscribing_contract_test.dart`. What belongs
    // here is vocabulary: the arity and the phase word, both readable off the
    // argument list alone.

    test('without a phase, it is a usage fault', () async {
      final r = await cli.run(['emit', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name> <phase>'));
    });

    test('a phase that is not Git\'s own word is a usage fault', () async {
      final r = await cli.run(['emit', 't.chat', 'sideways']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('prepared, committed or aborted'));
    });
  });

  group('--actor-email, against real Git', () {
    // FakeGit models no environment, so it cannot witness a claim about what
    // wins when a caller's stated actor and the ambient `GIT_AUTHOR_*` disagree
    // — only real Git signs anything. And `Platform.environment` is fixed for
    // the life of this process, so the poisoned half is a child born dirty, the
    // same device `construction_test.dart`'s poisoned-port gate uses.
    const git = ProcessGit();
    late Directory scratch;
    late Directory root;

    setUp(() async {
      scratch = Directory(Directory.systemTemp
          .createTempSync('entity_actor_email_')
          .resolveSymbolicLinksSync());
      root = Directory(p.join(scratch.path, 'site'))..createSync(recursive: true);
      Directory(p.join(root.path, '.place')).createSync(recursive: true);
      File(p.join(root.path, '.place', 'place.yaml'))
          .writeAsStringSync('name: site\n');
      await runWithGitAsync(git, () async {
        final runner =
            EntityRunner(out: StringBuffer(), err: StringBuffer(), currentDirectory: root.path);
        await runner.run(['create', 't.chat', ...Cli.signed]);
        await runner.run(['new', 't.chat', 'c1']);
      });
    });
    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    Future<Run> here(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = EntityRunner(out: out, err: err, currentDirectory: root.path);
      await runWithGitAsync(git, () => runner.run(args));
      return (out: out.toString(), err: err.toString(), code: runner.exitCode);
    }

    test(
        'a commit whose stated actor and whose ambient environment disagree '
        'is signed as the stated actor', () async {
      final opened = await here(['work', 't.chat:c1']);
      final parts = opened.out.trim().split('\t');
      File(p.join(parts[0], '1.txt')).writeAsStringSync('hi');

      // Before `--actor-email` existed, an honest caller who would not sign
      // under a fabricated `alice@entity.local` had only one door left: omit
      // `--actor` entirely — and this poisoned ambient is exactly what then
      // signed the commit instead.
      final child = await Process.run(
        Platform.resolvedExecutable,
        [
          'run', 'test/entity/tools/forged_actor_port.dart',
          root.path, 't.chat:c1', 'prompt', parts[0], parts[1],
          'alice', 'alice@real',
        ],
        workingDirectory: Directory.current.path,
        environment: {
          'GIT_AUTHOR_NAME': 'mallory',
          'GIT_AUTHOR_EMAIL': 'mallory@evil',
          'GIT_COMMITTER_NAME': 'mallory',
          'GIT_COMMITTER_EMAIL': 'mallory@evil',
        },
      );
      expect(child.exitCode, 0, reason: '${child.stderr}');

      final landed = git.showCommit(
        repositoryOf(root.path, 't.chat'),
        Commit((child.stdout as String).trim()),
      );
      expect(landed.author.name, 'alice');
      expect(landed.author.email, 'alice@real');
    });

    test('--actor-email without --actor is a usage fault', () async {
      final opened = await here(['work', 't.chat:c1']);
      final parts = opened.out.trim().split('\t');

      final r = await here([
        'commit', 't.chat:c1', 'prompt',
        '-w', parts[0], '--parent', parts[1], '--actor-email', 'nobody@nowhere',
      ]);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('--actor-email'));
    });
  });
}
