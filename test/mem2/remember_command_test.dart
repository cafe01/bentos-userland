import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem remember — acceptance', () {
    late MemHabitat hab;

    setUp(() {
      hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
    });

    Future<(String, String, int)> run(List<String> args, {String? stdin}) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        fileSystem: hab.fs,
        clock: hab.now,
        home: hab.home,
        environment: {'BENTOS_AGENT': hab.entity},
        stdinContent: stdin,
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    String? read(String placePath, String topic) {
      final f = hab.fs.file(
        hab.fs.path.join(placePath, '.place', 'mem', hab.entity, '$topic.md'),
      );
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    test('create requires --type and --attention', () async {
      final (_, err1, c1) = await run(
          ['remember', '-p', '/hq/cto', 'topic', '-A', '0.6'], stdin: 'body');
      expect(c1, 1);
      expect(err1, contains('--type'));

      final (_, err2, c2) = await run(
          ['remember', '-p', '/hq/cto', 'topic', '-t', 'semantic'], stdin: 'body');
      expect(c2, 1);
      expect(err2, contains('--attention'));
    });

    test('off-notch --attention is rejected', () async {
      final (_, err, code) = await run(
          ['remember', '-p', '/hq/cto', 'topic', '-t', 'semantic', '-A', '0.75'],
          stdin: 'body');
      expect(code, 1);
      expect(err, contains('off-notch'));
    });

    test('body from stdin lands at the vantage, slashes nest', () async {
      final (out, _, code) = await run([
        'remember', '-p', '/hq/cto', 'agency/spawn', '-t', 'procedural', '-A', '0.6',
      ], stdin: 'the keystone');
      expect(code, 0);
      final landed = read('/hq/cto', 'agency/spawn');
      expect(landed, isNotNull);
      expect(landed, contains('the keystone'));
      expect(landed, contains('type: procedural'));
      expect(out, contains('remembered  agency/spawn  (procedural · a:0.6)'));
    });

    test('body from --file lands too', () async {
      hab.fs.directory('/tmp').createSync(recursive: true);
      hab.fs.file('/tmp/note.md').writeAsStringSync('file-sourced body');
      final (_, _, code) = await run([
        'remember', '-p', '/hq/cto', 'note', '-t', 'semantic', '-A', '0.5', '-f', '/tmp/note.md',
      ]);
      expect(code, 0);
      expect(read('/hq/cto', 'note'), contains('file-sourced body'));
    });

    test('replacing an inherited topic rewrites the ancestor page in place — no local shadow', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'old body'));
      final (out, _, code) = await run([
        'remember', '-p', '/hq/cto', 'founders', '-t', 'semantic', '-A', '1.0',
      ], stdin: 'new body');
      expect(code, 0);
      expect(read('/hq', 'founders'), contains('new body'), reason: 'ancestor rewritten in place');
      expect(read('/hq/cto', 'founders'), isNull, reason: 'no local shadow');
      expect(out, contains('@${hab.resolver.enclosing('/hq').name}'));
    });

    test('--tag is repeatable and replaces', () async {
      final (_, _, _) = await run([
        'remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5',
        '--tag', 'a', '--tag', 'b',
      ], stdin: 'body');
      final page = MemPage.parse('t', read('/hq/cto', 't')!);
      expect(page.fields.tags, ['a', 'b']);
    });

    test('created and modified are stamped by the organ', () async {
      await run(['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5'],
          stdin: 'body');
      final page = MemPage.parse('t', read('/hq/cto', 't')!);
      expect(page.fields.created, MemHabitat.clock);
      expect(page.fields.modified, MemHabitat.clock);
    });

    test('a create with no body fails', () async {
      final (_, err, code) =
          await run(['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5']);
      expect(code, 1);
      expect(err, contains('no body'));
      expect(read('/hq/cto', 't'), isNull);
    });
  });
}
