import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The acting family of the coreutil: the bracket with a command as its body,
/// content read at a ref, and the worktree someone looks at.
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

  /// A body: a real program on disk, run inside the private area.
  List<String> writes(String path, String content) =>
      ['sh', '-c', 'printf %s ${_quote(content)} > $path'];

  group('entity act', () {
    test('the body writes, the act lands, and stdout is only the sha',
        () async {
      final r = await cli.run(
        ['act', 't.chat:c1', 'prompt', '--actor', 'alfred', '--', ...writes('1.txt', 'hello')],
      );

      expect(r.code, 0);
      expect(r.out.trim(), hasLength(40));

      final read = await cli.run(['read', 't.chat:c1:1.txt']);
      expect(read.out, 'hello');
    });

    test('the act is declared under the noun the caller gave it', () async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--actor', 'alfred', '--', ...writes('1.txt', 'hello')]);

      final log = await cli.run(['log', 't.chat:c1']);
      expect(log.out, contains('\tprompt\talfred\t'));
    });

    test('--say rides along, and the log reads as who did what', () async {
      await cli.run([
        'act', 't.chat:c1', 'prompt', '--actor', 'cafe',
        '--say', 'user say', '--', ...writes('1.txt', 'hello'),
      ]);

      final log = await cli.run(['log', 't.chat:c1']);
      expect(log.out.trim().split('\t').last, 'user say');

      final shown = await cli.run([
        'show', 't.chat:c1', log.out.trim().split('\t').first,
      ]);
      expect(shown.out, contains('say\tuser say'));
      expect(shown.out, contains('action\tprompt'),
          reason: 'the noun is what it always was');
    });

    test('an act that said nothing leaves the column empty and says no more',
        () async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'a')]);

      final log = await cli.run(['log', 't.chat:c1']);
      // The raw line, not a trimmed one: a trailing empty field is exactly what
      // `trim` eats, and the column is still there.
      final fields = log.out.split('\n').first.split('\t');
      expect(fields, hasLength(5));
      expect(fields.last, isEmpty);

      final shown = await cli.run(['show', 't.chat:c1', fields.first]);
      expect(shown.out, isNot(contains('say\t')),
          reason: 'an empty field would claim the act declared one and left it blank');
    });

    test('a talkative body does not pollute the answer', () async {
      final r = await cli.run([
        'act', 't.chat:c1', 'prompt', '--',
        'sh', '-c', 'echo chatter; printf hi > 1.txt',
      ]);

      expect(r.code, 0);
      expect(r.out.trim(), hasLength(40), reason: 'stdout carries the sha alone');
      expect(r.err, contains('chatter'));
    });

    test('a body that fails lands nothing and answers with its own number',
        () async {
      final before = (await cli.run(['ls', 't.chat'])).out;

      final r = await cli.run([
        'act', 't.chat:c1', 'prompt', '--',
        'sh', '-c', 'printf hi > 1.txt; exit 7',
      ]);

      expect(r.code, 7);
      expect(r.out, isEmpty);
      expect((await cli.run(['ls', 't.chat'])).out, before,
          reason: 'the tip did not move');
      expect((await cli.run(['log', 't.chat:c1'])).out, isEmpty);
    });

    test('the area is released whether the body succeeded or not', () async {
      final before = _actAreas(site);

      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'a')]);
      await cli.run(['act', 't.chat:c1', 'prompt', '--', 'sh', '-c', 'exit 1']);

      expect(_actAreas(site), before);
    });

    test('without a body, it is a usage fault', () async {
      final r = await cli.run(['act', 't.chat:c1', 'prompt']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('-- <command>'));
    });

    test('there is no verb that asks the entity to do something', () async {
      // `act` frames the caller's own write. The absence of an invoke verb is
      // the model, not an omission.
      final r = await cli.run(['invoke', 't.chat:c1', 'prompt']);
      expect(r.code, EntityRunner.usageCode);
    });
  });

  group('entity read', () {
    test('reads at the ref, with no worktree anywhere', () async {
      final landed = await cli.run([
        'act', 't.chat:c1', 'prompt', '--',
        'sh', '-c', 'mkdir -p a && printf %s deep > a/b.txt',
      ]);
      expect(landed.code, 0, reason: landed.err);

      final r = await cli.run(['read', 't.chat:c1:a/b.txt']);
      expect(r.code, 0);
      expect(r.out, 'deep');
      expect(Directory('${site.root.path}/t.chat').existsSync(), isFalse);
    });

    test('--as-of reads the content as it stood at that act', () async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'first')]);
      final log = await cli.run(['log', 't.chat:c1']);
      final first = log.out.trim().split('\t').first;
      await cli.run(['act', 't.chat:c1', 'reply', '--', ...writes('1.txt', 'second')]);

      expect((await cli.run(['read', 't.chat:c1:1.txt'])).out, 'second');

      final r = await cli.run(['read', 't.chat:c1:1.txt', '--as-of', first]);
      expect(r.code, 0);
      expect(r.out, 'first',
          reason: 'a validator judges an act where it was taken, never here');
    });

    test('a coordinate with no path is a usage fault', () async {
      final r = await cli.run(['read', 't.chat:c1']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<path>'));
    });
  });

  group('entity materialize', () {
    test('--at stands the files where someone can look at them', () async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'hello')]);
      final where = '${site.root.path}/face';

      final r = await cli.run(['materialize', 't.chat:c1', '--at', where]);
      expect(r.code, 0);
      expect(r.out.trim(), where);
      expect(File('$where/1.txt').readAsStringSync(), 'hello');
    });

    test('without --at, the face stands on the ground of the place that holds it',
        () async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'hello')]);

      final r = await cli.run(['materialize', 't.chat:c1']);
      expect(r.code, 0);
      final where = r.out.trim();

      expect(where, startsWith(site.root.path),
          reason: 'a private area is born in the plot, never in the machine');
      expect(File('$where/1.txt').readAsStringSync(), 'hello');
    });

    test('an instance that was never born cannot be looked at', () async {
      final r = await cli.run(['materialize', 't.chat:ghost']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('not born'));
    });
  });

  group('entity refresh', () {
    /// A face standing where someone looks, and the path it stands at.
    Future<String> face() async {
      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'first')]);
      final where = '${site.root.path}/face';
      await cli.run(['materialize', 't.chat:c1', '--at', where]);
      return where;
    }

    test('a face lags until it is refreshed, and then it does not', () async {
      final where = await face();
      await cli.run(['act', 't.chat:c1', 'reply', '--', ...writes('1.txt', 'second')]);

      expect(File('$where/1.txt').readAsStringSync(), 'first',
          reason: 'nothing refreshes a face for whoever looks');

      final r = await cli.run(['refresh', 't.chat:c1', where]);
      expect(r.code, 0);
      expect(File('$where/1.txt').readAsStringSync(), 'second');
      expect(r.out.trim(), (await cli.run(['tip', 't.chat:c1'])).out.trim());
    });

    test('a face already at the tip answers with it, and refreshes again',
        () async {
      // Idempotent on purpose: a face that polls asks a second time, and the
      // second answer is not an error. What this cannot say is whether the
      // early return inside the library fired — standing still and standing
      // up again at the same commit are indistinguishable from out here.
      final where = await face();

      final once = await cli.run(['refresh', 't.chat:c1', where]);
      final twice = await cli.run(['refresh', 't.chat:c1', where]);
      expect(once.code, 0);
      expect(twice.out.trim(), once.out.trim());
      expect(once.out.trim(), (await cli.run(['tip', 't.chat:c1'])).out.trim());
      expect(File('$where/1.txt').readAsStringSync(), 'first');
    });

    test('it is another process — nothing of the one that looked survives',
        () async {
      final where = await face();
      await cli.run(['act', 't.chat:c1', 'reply', '--', ...writes('1.txt', 'second')]);

      // The coordinate is the only thing carried in: the directory reports its
      // repository and its commit, and never the ref it follows.
      final r = await cli.run(['refresh', 't.chat:c1', where], cwd: site.root.path);
      expect(r.code, 0);
      expect(File('$where/1.txt').readAsStringSync(), 'second');
    });

    test('a directory nobody materialized is not found', () async {
      final r = await cli.run(['refresh', 't.chat:c1', '${site.root.path}/nowhere']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('no worktree'));
    });

    test('a released face is not found either', () async {
      final where = await face();
      await cli.run(['release', where]);

      final r = await cli.run(['refresh', 't.chat:c1', where]);
      expect(r.code, EntityRunner.notFoundCode);
    });

    test('without a path, it is a usage fault', () async {
      final r = await cli.run(['refresh', 't.chat:c1']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<path>'));
    });
  });
}

/// The act areas standing in **this site's** ground — what a released workspace
/// must leave none of.
///
/// Measured at the installation's own slice and nowhere else. Counting the
/// machine's temp made the assertion depend on every other process on the box:
/// a parallel sibling's area read as this site's leak, and the debris of past
/// runs fattened the count for nobody's reason. Locality is what lets the suite
/// run concurrently at all.
Set<String> _actAreas(Site site) {
  final ground = Directory(
      p.join(p.dirname(repositoryOf(site.root.path, 't.chat')), 'acts'));
  if (!ground.existsSync()) return const {};
  return ground.listSync().map((e) => e.path).toSet();
}

String _quote(String text) => "'${text.replaceAll("'", r"'\''")}'";
