import 'dart:io';

import 'package:bentos_userland/entity.dart';
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
      final before = _tempAreas();

      await cli.run(['act', 't.chat:c1', 'prompt', '--', ...writes('1.txt', 'a')]);
      await cli.run(['act', 't.chat:c1', 'prompt', '--', 'sh', '-c', 'exit 1']);

      expect(_tempAreas(), before);
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

    test('an instance that was never born cannot be looked at', () async {
      final r = await cli.run(['materialize', 't.chat:ghost']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('not born'));
    });
  });
}

/// The private areas standing in the system's temp — what a released workspace
/// must leave none of.
Set<String> _tempAreas() => Directory.systemTemp
    .listSync()
    .map((e) => e.path)
    .where((path) => path.contains('entity-act-'))
    .toSet();

String _quote(String text) => "'${text.replaceAll("'", r"'\''")}'";
