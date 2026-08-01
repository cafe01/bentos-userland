import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem survey — acceptance', () {
    Future<(String, String, int)> run(
      MemHabitat hab,
      List<String> args, {
      Map<String, String>? environment,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        clock: hab.now,
        environment: environment ?? {'BENTOS_AGENT': hab.bank},
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    test('bare survey lists the whole cascaded map, grouped, 0.0 included', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
        hab.seed('/hq/cto', 'idle', MemHabitat.page('prospective', '0.0', 'b'));
        final (out, _, code) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(code, 0);
        expect(out, contains('founders'));
        expect(out, contains('idle'), reason: '0.0 is included in the bare map');
      });
    });

    test('one unreadable page costs its own line, never the bank', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
        hab.seed('/hq/cto', 'broken',
            '---\ntype: semantic\nattention: 1.0\ngist: **diary** — an alias\n---\n\nb\n');
        final (out, err, code) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(code, 0);
        expect(out, contains('founders'), reason: 'the rest of the map survives');
        expect(err, contains('unreadable page broken'));
      });
    });

    test('--warm selects the band, boundary inclusive', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'w7', MemHabitat.page('semantic', '0.7', 'a'));
        hab.seed('/hq/cto', 'w9', MemHabitat.page('semantic', '0.9', 'b'));
        hab.seed('/hq/cto', 'hot', MemHabitat.page('semantic', '1.0', 'c'));
        final (out, _, _) = await run(hab, ['survey', '-p', '/hq/cto', '--warm']);
        expect(out, contains('w7'));
        expect(out, contains('w9'));
        expect(out, isNot(contains('  1.0  hot')));
      });
    });

    test('--type shows only that mode', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'sem', MemHabitat.page('semantic', '0.5', 'a'));
        hab.seed('/hq/cto', 'proc', MemHabitat.page('procedural', '0.5', 'b'));
        final (out, _, _) =
            await run(hab, ['survey', '-p', '/hq/cto', '--type', 'semantic']);
        expect(out, contains('sem'));
        expect(out, isNot(contains('proc')));
      });
    });

    test('inherited pages carry @place', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '0.8', 'a'));
        final (out, _, _) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(out, contains('@${Place('/hq').name}'));
      });
    });

    test('an untouched bank is begin-one guidance on stderr, exit 0', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (out, err, code) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(out, contains('bank:'), reason: 'the bank is named either way');
        expect(err, contains('no pages yet'));
        expect(code, 0, reason: 'an empty brain is a fact, not a failure');
      });
    });

    test('a reach that matches nothing is a normal answer, exit 0', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'sem', MemHabitat.page('semantic', '0.5', 'a'));
        final (_, err, code) =
            await run(hab, ['survey', '-p', '/hq/cto', '--hot']);
        expect(code, 0);
        expect(err, isNot(contains('no pages yet')),
            reason: 'the bank is populated — this is a filter miss, not a newborn');
        expect(err, contains('no pages under'));
        expect(err, contains('1.0'), reason: 'the reach is echoed back');
      });
    });

    test('the map reports its own weight, named by register, on stderr',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'sem', MemHabitat.page('semantic', '0.5', 'a'));
        final (out, err, _) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(out, isNot(contains('· survey ·')),
            reason: 'the total never enters the stdout that becomes a mind');
        expect(err, contains('· survey · 1 pages'),
            reason: 'the verb names which register the words are counted in');
      });
    });

    test('absent bank with no \$BENTOS_AGENT errors with guidance', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) =
            await run(hab, ['survey', '-p', '/hq/cto'], environment: const {});
        expect(err, contains('no bank'));
        expect(code, 1);
      });
    });
  });
}
