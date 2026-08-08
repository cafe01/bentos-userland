import 'dart:io';

import 'package:bentos_userland/src/mem2/gist_deriver.dart';
import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem gist — acceptance', () {
    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    /// The model seam, stubbed — no gate here makes a live `llm` call. Answers
    /// with the body's first word so an assert can tell one page's cue from
    /// another's.
    Future<String> cue(String body) async => 'cue for ${body.split(' ').first}';

    Future<(String, String, int)> run(
      MemHabitat hab,
      List<String> args, {
      GistLlm? llm,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        clock: hab.now,
        environment: {'BENTOS_AGENT': hab.bank},
        gistLlm: llm ?? cue,
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    String raw(MemHabitat hab, String placePath, String topic) =>
        File(p.join(placePath, '${hab.bank}.mem', '$topic.md')).readAsStringSync();

    MemPage page(MemHabitat hab, String placePath, String topic) =>
        MemPage.parse(topic, raw(hab, placePath, topic));

    test('re-derives one page, and only the gist line moves', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'front',
            // Seeded exactly as the organ writes a page — gist quoted included —
            // so the byte comparison below measures this verb and not the
            // difference between a hand-written page and a written one.
            '---\ntype: prospective\nattention: 0.8\ncreated: 2026-05-01T00:00:00.000Z\nmodified: 2026-06-01T00:00:00.000Z\ngist: "the old summary"\n---\n\nalpha body\n');
        final before = raw(hab, '/hq/cto', 'front');

        final (out, _, code) = await run(hab, ['gist', '-p', '/hq/cto', 'front']);
        expect(code, 0);

        final after = raw(hab, '/hq/cto', 'front');
        // The witness for "modified does not move" is the whole file, not the
        // stamp read back: every byte outside the gist line must be identical.
        expect(
          after.replaceFirst('gist: "cue for alpha"', 'gist: "the old summary"'),
          before,
          reason: 'organ-written page byte-identical apart from the gist line',
        );
        final pg = page(hab, '/hq/cto', 'front');
        expect(pg.fields.gist, 'cue for alpha');
        expect(pg.fields.modified, DateTime.utc(2026, 6, 1));
        expect(pg.fields.created, DateTime.utc(2026, 5, 1));
        expect(pg.body, 'alpha body');
        // The old text is deleted, so the echo measures instead of quoting it:
        // the shrink on the first row, the new cue alone on the second.
        expect(out, contains('gist  front  3w → 3w\n      cue for alpha'));
        expect(out, isNot(contains('the old summary')));
      });
    });

    test('a page with no gist gains one, and a multi-line scalar is replaced whole',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'absent',
            '---\ntype: semantic\nattention: 0.7\n---\n\nalpha body\n');
        hab.seed('/hq/cto', 'folded',
            '---\ntype: semantic\nattention: 0.7\ngist: >-\n  a gist spilled\n  over two lines\n---\n\nbeta body\n');

        final (_, _, code) =
            await run(hab, ['gist', '-p', '/hq/cto', 'absent', 'folded']);
        expect(code, 0);

        expect(page(hab, '/hq/cto', 'absent').fields.gist, 'cue for alpha');
        final folded = page(hab, '/hq/cto', 'folded');
        expect(folded.fields.gist, 'cue for beta');
        expect(folded.body, 'beta body',
            reason: 'the continuation line did not survive into the body');
      });
    });

    test('a band re-derives every selected page, hot and cool alike', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a',
            '---\ntype: semantic\nattention: 0.8\ngist: old a\n---\n\nalpha body\n');
        hab.seed('/hq/cto', 'b',
            '---\ntype: semantic\nattention: 0.7\ngist: old b\n---\n\nbeta body\n');
        hab.seed('/hq/cto', 'c',
            '---\ntype: semantic\nattention: 0.2\ngist: a gist of four words\n---\n\ngamma body\n');

        final (out, err, code) = await run(hab, ['gist', '-p', '/hq/cto', '--warm']);
        expect(code, 0);
        expect(page(hab, '/hq/cto', 'a').fields.gist, 'cue for alpha');
        expect(page(hab, '/hq/cto', 'b').fields.gist, 'cue for beta');
        expect(page(hab, '/hq/cto', 'c').fields.gist, 'a gist of four words',
            reason: 'outside the reach');
        // The band closes on the corpus measurement the migration is for: two
        // pages of 2w each in, two cues of 3w each out — and the untouched cool
        // page is in neither total.
        expect(err,
            contains('mem: john · gist · 2 re-derived · 0 failed · 4w → 6w'));
        expect(out, contains('gist  a  2w → 3w\n      cue for alpha'));
      });
    });

    test('one failure names its page and the band continues', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a',
            '---\ntype: semantic\nattention: 0.8\ngist: old a\n---\n\nalpha body\n');
        hab.seed('/hq/cto', 'b',
            '---\ntype: semantic\nattention: 0.8\ngist: old b\n---\n\nbeta body\n');

        Future<String> flaky(String body) async {
          if (body.startsWith('alpha')) {
            throw const GistDerivationFailed('llm exited 1');
          }
          return cue(body);
        }

        final (_, err, code) =
            await run(hab, ['gist', '-p', '/hq/cto', '--warm'], llm: flaky);
        expect(code, 1);
        expect(page(hab, '/hq/cto', 'a').fields.gist, 'old a',
            reason: 'a refused derivation leaves the page as it was');
        expect(page(hab, '/hq/cto', 'b').fields.gist, 'cue for beta',
            reason: 'the rest of the band still ran');
        expect(err, contains('mem: a: gist derivation failed'));
        expect(err, contains('1 re-derived · 1 failed'));
        expect(err, contains('2w → 3w'),
            reason: 'the totals count what landed, not what was attempted');
      });
    });

    test('--set writes the line by hand and never reaches the seam', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'front',
            '---\ntype: semantic\nattention: 0.8\ngist: old\n---\n\nalpha body\n');
        Future<String> never(String body) async => fail('the seam was reached');

        final (_, _, code) = await run(
            hab, ['gist', '-p', '/hq/cto', 'front', '--set', 'a hand-written cue'],
            llm: never);
        expect(code, 0);
        expect(page(hab, '/hq/cto', 'front').fields.gist, 'a hand-written cue');
      });
    });

    test('a poisonous cue round-trips through write, parse and re-read', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'front',
            '---\ntype: semantic\nattention: 0.8\n---\n\nalpha body\n');
        const nasty = '*bold* — a cue: with # a hash, a "quote" and a \\ slash';
        final (_, _, code) = await run(
            hab, ['gist', '-p', '/hq/cto', 'front', '--set', nasty]);
        expect(code, 0);
        expect(page(hab, '/hq/cto', 'front').fields.gist, nasty);

        // And the whole bank still reads — one poisoned page freezing every
        // later write is the failure this guards.
        final (survey, _, surveyCode) = await run(hab, ['survey', '-p', '/hq/cto']);
        expect(surveyCode, 0);
        expect(survey, contains(nasty));
      });
    });

    test('an inherited page is re-gisted where it lives, with no local shadow',
        () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders',
            '---\ntype: semantic\nattention: 0.7\ngist: old\n---\n\nalpha body\n');
        final (_, _, code) = await run(hab, ['gist', '-p', '/hq/cto', 'founders']);
        expect(code, 0);
        expect(page(hab, '/hq', 'founders').fields.gist, 'cue for alpha');
        expect(File('/hq/cto/${hab.bank}.mem/founders.md').existsSync(), isFalse);
      });
    });

    test('an empty selection is a clean no-op', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (out, _, code) =
            await run(hab, ['gist', '-p', '/hq/cto', '--tag', 'ghost']);
        expect(code, 0);
        expect(out, contains('no pages matched'));
      });
    });

    test('--set refuses a band', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a', MemHabitat.page('semantic', '0.8', 'alpha body'));
        final (_, err, code) =
            await run(hab, ['gist', '-p', '/hq/cto', '--warm', '--set', 'x']);
        expect(code, 1);
        expect(err, contains('exactly one <topic>'));
      });
    });
  });
}
