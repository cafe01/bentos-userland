import 'dart:io';

import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem refocus — acceptance', () {
    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    Future<(String, String, int)> run(MemHabitat hab, List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        clock: hab.now,
        environment: {'BENTOS_AGENT': hab.bank},
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    MemPage page(MemHabitat hab, String placePath, String topic) => MemPage.parse(
        topic,
        File(p.join(placePath, '${hab.bank}.mem', '$topic.md')).readAsStringSync());

    test('refocus <topic> --to sets one page, body and modified untouched', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'front',
            '---\ntype: prospective\nattention: 0.8\nmodified: 2026-06-01T00:00:00.000Z\n---\n\nthe body\n');
        final (out, _, code) = await run(hab, ['refocus', '-p', '/hq/cto', 'front', '--to', '1.0']);
        expect(code, 0);
        final p = page(hab, '/hq/cto', 'front');
        expect(p.fields.attention.render(), '1.0');
        expect(p.body, 'the body', reason: 'body byte-identical');
        expect(p.fields.modified, DateTime.utc(2026, 6, 1), reason: 'modified unchanged');
        expect(out, contains('refocused  front  0.8 → 1.0'));
      });
    });

    test('an inherited page refocuses where it lives', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '0.7', 'body'));
        final (_, _, code) = await run(hab, ['refocus', '-p', '/hq/cto', 'founders', '--to', '0.4']);
        expect(code, 0);
        expect(page(hab, '/hq', 'founders').fields.attention.render(), '0.4');
        final shadow = File('/hq/cto/${hab.bank}.mem/founders.md');
        expect(shadow.existsSync(), isFalse, reason: 'no local shadow');
      });
    });

    test('refocus --tag --to sets every tagged page (bulk)', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a',
            '---\ntype: semantic\nattention: 0.8\ntags: [front]\n---\n\na\n');
        hab.seed('/hq/cto', 'b',
            '---\ntype: semantic\nattention: 0.5\ntags: [front]\n---\n\nb\n');
        final (out, _, code) =
            await run(hab, ['refocus', '-p', '/hq/cto', '--tag', 'front', '--to', '0.2']);
        expect(code, 0);
        expect(page(hab, '/hq/cto', 'a').fields.attention.render(), '0.2');
        expect(page(hab, '/hq/cto', 'b').fields.attention.render(), '0.2');
        expect(out, contains('refocused 2 pages  (tag:front)'));
      });
    });

    test('--by shifts relatively and clamps at the rail, visibly', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a',
            '---\ntype: semantic\nattention: 0.3\ntags: [front]\n---\n\na\n');
        final (out, _, code) =
            await run(hab, ['refocus', '-p', '/hq/cto', '--tag', 'front', '--by', '-0.4']);
        expect(code, 0);
        expect(page(hab, '/hq/cto', 'a').fields.attention.render(), '0.0');
        expect(out, contains('0.3 → 0.0'));
        expect(out, contains('(clamped)'));
      });
    });

    test('--by refuses to move an assumed attention; --to still may', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'degraded', '---\ntype: semantic\n---\n\nx\n');

        final (_, errBy, codeBy) =
            await run(hab, ['refocus', '-p', '/hq/cto', 'degraded', '--by', '0.2']);
        expect(codeBy, 1);
        expect(errBy, contains('assumed attention'));

        final (_, _, codeTo) =
            await run(hab, ['refocus', '-p', '/hq/cto', 'degraded', '--to', '0.6']);
        expect(codeTo, 0);
        expect(page(hab, '/hq/cto', 'degraded').fields.attention.render(), '0.6');
        expect(page(hab, '/hq/cto', 'degraded').isDegraded, isFalse,
            reason: 'the stated value replaces the guess');
      });
    });

    test('an empty selection is a clean no-op, not an error', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (out, _, code) =
            await run(hab, ['refocus', '-p', '/hq/cto', '--tag', 'ghost', '--to', '0.2']);
        expect(code, 0);
        expect(out, contains('no pages matched'));
      });
    });

    test('exactly one of --to / --by is required', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) = await run(hab, ['refocus', '-p', '/hq/cto', 'front']);
        expect(code, 1);
        expect(err, contains('exactly one'));
      });
    });
  });
}
