import 'dart:io';

import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem remember — acceptance', () {
    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    Future<(String, String, int)> run(
      MemHabitat hab,
      List<String> args, {
      String? stdin,
      Future<String> Function(String body)? gistLlm,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        clock: hab.now,
        environment: {'BENTOS_AGENT': hab.bank},
        stdinReader: stdin == null ? null : () async => stdin,
        gistLlm: gistLlm ?? (body) async => 'stub gist',
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    String? read(MemHabitat hab, String placePath, String topic) {
      final f = File(p.join(placePath, '${hab.bank}.mem', '$topic.md'));
      return f.existsSync() ? f.readAsStringSync() : null;
    }

    test('create requires --type and --attention', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err1, c1) = await run(
            hab, ['remember', '-p', '/hq/cto', 'topic', '-A', '0.6'], stdin: 'body');
        expect(c1, 1);
        expect(err1, contains('--type'));

        final (_, err2, c2) = await run(
            hab, ['remember', '-p', '/hq/cto', 'topic', '-t', 'semantic'], stdin: 'body');
        expect(c2, 1);
        expect(err2, contains('--attention'));
      });
    });

    test('off-notch --attention is rejected', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) = await run(
            hab, ['remember', '-p', '/hq/cto', 'topic', '-t', 'semantic', '-A', '0.75'],
            stdin: 'body');
        expect(code, 1);
        expect(err, contains('off-notch'));
      });
    });

    test('body from stdin lands at the vantage, slashes nest', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (out, _, code) = await run(hab, [
          'remember', '-p', '/hq/cto', 'agency/spawn', '-t', 'procedural', '-A', '0.6',
        ], stdin: 'the keystone');
        expect(code, 0);
        final landed = read(hab, '/hq/cto', 'agency/spawn');
        expect(landed, isNotNull);
        expect(landed, contains('the keystone'));
        expect(landed, contains('type: procedural'));
        expect(out, contains('remembered  agency/spawn  (procedural · a:0.6)'));
      });
    });

    test('body from --file lands too', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        Directory('/tmp').createSync(recursive: true);
        File('/tmp/note.md').writeAsStringSync('file-sourced body');
        final (_, _, code) = await run(hab, [
          'remember', '-p', '/hq/cto', 'note', '-t', 'semantic', '-A', '0.5', '-f', '/tmp/note.md',
        ]);
        expect(code, 0);
        expect(read(hab, '/hq/cto', 'note'), contains('file-sourced body'));
      });
    });

    test('replacing an inherited topic rewrites the ancestor page in place — no local shadow',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'old body'));
        final (out, _, code) = await run(hab, [
          'remember', '-p', '/hq/cto', 'founders', '-t', 'semantic', '-A', '1.0',
        ], stdin: 'new body');
        expect(code, 0);
        expect(read(hab, '/hq', 'founders'), contains('new body'),
            reason: 'ancestor rewritten in place');
        expect(read(hab, '/hq/cto', 'founders'), isNull, reason: 'no local shadow');
        expect(out, contains('@${Place('/hq').name}'));
      });
    });

    test('--tag is repeatable and replaces', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        await run(hab, [
          'remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5',
          '--tag', 'a', '--tag', 'b',
        ], stdin: 'body');
        final page = MemPage.parse('t', read(hab, '/hq/cto', 't')!);
        expect(page.fields.tags, ['a', 'b']);
      });
    });

    test('created and modified are stamped by the organ', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        await run(hab, ['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5'],
            stdin: 'body');
        final page = MemPage.parse('t', read(hab, '/hq/cto', 't')!);
        expect(page.fields.created, MemHabitat.clock);
        expect(page.fields.modified, MemHabitat.clock);
      });
    });

    test('a body write with no --gist auto-derives the gist', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        await run(hab, ['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5'],
            stdin: 'body', gistLlm: (body) async => 'open here for the derived line');
        final page = MemPage.parse('t', read(hab, '/hq/cto', 't')!);
        expect(page.fields.gist, 'open here for the derived line');
      });
    });

    test('an explicit --gist wins and skips derivation', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        var called = false;
        await run(hab, [
          'remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5', '--gist', 'hand-written',
        ], stdin: 'body', gistLlm: (body) async {
          called = true;
          return 'derived';
        });
        final page = MemPage.parse('t', read(hab, '/hq/cto', 't')!);
        expect(page.fields.gist, 'hand-written');
        expect(called, isFalse, reason: 'the seam is never touched when --gist is given');
      });
    });

    test('a derivation failure surfaces and lands no page', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) = await run(
          hab,
          ['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5'],
          stdin: 'body',
          gistLlm: (body) async => throw Exception('model down'),
        );
        expect(code, 1);
        expect(err, contains('gist derivation failed'));
        expect(read(hab, '/hq/cto', 't'), isNull, reason: 'no page lands when the gist cannot be derived');
      });
    });

    test('a create with no body fails', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) =
            await run(hab, ['remember', '-p', '/hq/cto', 't', '-t', 'semantic', '-A', '0.5']);
        expect(code, 1);
        expect(err, contains('no body'));
        expect(read(hab, '/hq/cto', 't'), isNull);
      });
    });
  });
}
