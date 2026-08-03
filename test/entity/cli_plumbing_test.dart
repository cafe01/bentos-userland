import 'dart:io';

import 'package:bentos_userland/entity.dart';
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
    await cli.run(['create', 't.chat']);
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
        '-w', opened.area, '--parent', opened.parent, '--actor', 'alfred',
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
        '-w', opened.area, '--parent', opened.parent, '--actor', 'cafe',
        '--say', 'user say',
      ]);

      expect((await cli.run(['log', 't.chat:c1'])).out.trim().split('\t').last,
          'user say');
      await cli.run(['release', opened.area]);
    });

    test('a stale parent is refused, and refusal is not an error', () async {
      // Two actors read the same tip. The first lands; the second is holding a
      // value the ref no longer has, and the substrate refuses it under lock.
      final first = await work('t.chat:c1');
      final second = await work('t.chat:c1');
      expect(first.parent, second.parent);

      File('${first.area}/1.txt').writeAsStringSync('mine');
      final landed = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '-w', first.area, '--parent', first.parent],
      );
      expect(landed.code, 0);

      File('${second.area}/1.txt').writeAsStringSync('theirs');
      final refused = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '-w', second.area, '--parent', second.parent],
      );

      expect(refused.code, EntityRunner.refusedCode);
      expect(refused.err, contains('refused'));
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
        ['commit', 't.chat:c1', 'prompt', '-w', opened.area],
      );
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('--parent'));
    });

    test('commit without an area is a usage fault', () async {
      final r = await cli.run(
        ['commit', 't.chat:c1', 'prompt', '--parent', 'deadbeef'],
      );

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('-w'));
    });
  });
}
