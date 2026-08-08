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

    test('one unparseable page costs its own disclosure, never the bank', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
        hab.seed('/hq/cto', 'broken',
            '---\ntype: semantic\nattention: 1.0\ngist: **diary** — an alias\n---\n\nb\n');
        final (out, err, code) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(code, 0);
        expect(out, contains('founders'), reason: 'the rest of the map survives');
        expect(out, contains('broken'), reason: 'a degraded page is still on the map, prose intact');
        expect(err, contains('degraded page broken'));
      });
    });

    test('a bank with every named defect still surveys whole and accepts an unrelated write', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'ok', MemHabitat.page('semantic', '0.5', 'fine'));
        hab.seed('/hq/cto', 'no-frontmatter', 'just prose, no header at all');
        hab.seed('/hq/cto', 'bare-int', '---\ntype: semantic\nattention: 1\n---\n\nx\n');
        hab.seed('/hq/cto', 'no-type', '---\nattention: 0.5\n---\n\ny\n');
        hab.seed('/hq/cto', 'truncated', '---\ntype: semantic\nattention: 0.5\nno closing fence');

        final (survey, _, surveyCode) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(surveyCode, 0);
        for (final topic in ['ok', 'no-frontmatter', 'bare-int', 'no-type', 'truncated']) {
          expect(survey, contains(topic), reason: '$topic still on the map');
        }
        final bareIntLine = survey.split('\n').firstWhere((l) => l.contains('bare-int'));
        expect(bareIntLine, isNot(contains('⚠')), reason: 'the widened grammar never degrades');

        final (recall, _, recallCode) = await run(
            hab, ['recall', '-p', '/hq/cto', 'no-frontmatter', 'no-type', 'truncated']);
        expect(recallCode, 0);
        expect(recall, contains('just prose'));
        expect(recall, contains('y'));

        final (_, _, writeCode) = await run(hab, ['refocus', '-p', '/hq/cto', 'ok', '--to', '0.6']);
        expect(writeCode, 0, reason: 'an unrelated page still accepts a write');
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

    /// Five pages whose attention deliberately disagrees with both composition
    /// order and directory order, so "hottest" can be told from "first".
    void seedLadder(MemHabitat hab) {
      hab.seed('/hq/cto', 'aaa-cold', MemHabitat.page('semantic', '0.2', 'a'));
      hab.seed('/hq/cto', 'bbb-hot', MemHabitat.page('prospective', '1.0', 'b'));
      hab.seed('/hq/cto', 'ccc-warm', MemHabitat.page('semantic', '0.8', 'c'));
      hab.seed('/hq/cto', 'ddd-warmer', MemHabitat.page('procedural', '0.9', 'd'));
      hab.seed('/hq/cto', 'eee-cool', MemHabitat.page('semantic', '0.5', 'e'));
    }

    test('--limit takes the hottest n, not the first n', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        seedLadder(hab);
        final (out, _, code) =
            await run(hab, ['survey', '-p', '/hq/cto', '--limit', '2']);
        expect(code, 0);
        expect(out, contains('bbb-hot'));
        expect(out, contains('ddd-warmer'));
        // The two hottest are a prospective and a procedural — last and
        // second-last in composition order — so a map that cut in composition
        // or directory order would hold aaa-cold instead.
        expect(out, isNot(contains('aaa-cold')));
        expect(out, isNot(contains('ccc-warm')));
      });
    });

    test('the truncation notice appears when and only when the map was cut',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        seedLadder(hab);

        final (cut, cutErr, _) =
            await run(hab, ['survey', '-p', '/hq/cto', '--limit', '2']);
        expect(cut, contains('showing 1–2 of 5, hottest first'));
        expect(cut, contains('→ mem survey --offset 2'),
            reason: 'a tail remains, so the affordance is owed');
        expect(cutErr, contains('· 2 pages'));
        expect(cutErr, contains('(of 5)'),
            reason: 'the weight line reports what was rendered, and that it was cut');

        final (whole, wholeErr, _) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(whole, isNot(contains('showing')),
            reason: 'an unbounded map is silent about a bound it does not have');
        expect(wholeErr, isNot(contains('(of ')));

        final (exact, _, _) =
            await run(hab, ['survey', '-p', '/hq/cto', '--limit', '5']);
        expect(exact, isNot(contains('showing')),
            reason: 'a limit that cuts nothing is not a cut');
      });
    });

    test('--offset walks the tail, and the affordance stops at the end', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        seedLadder(hab);
        final (out, _, code) = await run(
            hab, ['survey', '-p', '/hq/cto', '--limit', '2', '--offset', '2']);
        expect(code, 0);
        expect(out, contains('showing 3–4 of 5, hottest first'));
        expect(out, contains('→ mem survey --offset 4'));
        expect(out, contains('ccc-warm'));
        expect(out, contains('eee-cool'));

        final (tail, _, _) =
            await run(hab, ['survey', '-p', '/hq/cto', '--offset', '4']);
        expect(tail, contains('showing 5–5 of 5, hottest first'));
        expect(tail, isNot(contains('--offset 5')),
            reason: 'a next-page hint with no next page is the lie inverted');
      });
    });

    test('an offset past the end says so, and does not call the bank empty',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        seedLadder(hab);
        final (_, err, code) =
            await run(hab, ['survey', '-p', '/hq/cto', '--offset', '99']);
        expect(code, 0);
        expect(err, contains('offset 99 is past the end'));
        expect(err, contains('5 pages'));
        expect(err, isNot(contains('no pages')));
      });
    });

    test('a bound that is not a non-negative number is refused', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        seedLadder(hab);
        final (_, err, code) =
            await run(hab, ['survey', '-p', '/hq/cto', '--limit', 'lots']);
        expect(code, 1);
        expect(err, contains('--limit takes a non-negative whole number'));

        final (_, negErr, negCode) =
            await run(hab, ['survey', '-p', '/hq/cto', '--offset', '-3']);
        expect(negCode, 1);
        expect(negErr, contains('--offset takes a non-negative whole number'));
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
