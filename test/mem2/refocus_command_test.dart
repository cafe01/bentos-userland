import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem refocus — acceptance', () {
    late MemHabitat hab;

    setUp(() {
      hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
    });

    Future<(String, String, int)> run(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        fileSystem: hab.fs,
        clock: hab.now,
        home: hab.home,
        environment: {'BENTOS_AGENT': hab.entity},
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    MemPage page(String placePath, String topic) =>
        MemPage.parse(topic, hab.fs
            .file(hab.fs.path.join(placePath, '.place', 'mem', hab.entity, '$topic.md'))
            .readAsStringSync());

    test('refocus <topic> --to sets one page, body and modified untouched', () async {
      hab.seed('/hq/cto', 'front',
          '---\ntype: prospective\nattention: 0.8\nmodified: 2026-06-01T00:00:00.000Z\n---\n\nthe body\n');
      final (out, _, code) = await run(['refocus', '-p', '/hq/cto', 'front', '--to', '1.0']);
      expect(code, 0);
      final p = page('/hq/cto', 'front');
      expect(p.fields.attention.render(), '1.0');
      expect(p.body, 'the body', reason: 'body byte-identical');
      expect(p.fields.modified, DateTime.utc(2026, 6, 1), reason: 'modified unchanged');
      expect(out, contains('refocused  front  0.8 → 1.0'));
    });

    test('an inherited page refocuses where it lives', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '0.7', 'body'));
      final (_, _, code) = await run(['refocus', '-p', '/hq/cto', 'founders', '--to', '0.4']);
      expect(code, 0);
      expect(page('/hq', 'founders').fields.attention.render(), '0.4');
      final shadow = hab.fs.file('/hq/cto/.place/mem/${hab.entity}/founders.md');
      expect(shadow.existsSync(), isFalse, reason: 'no local shadow');
    });

    test('refocus --tag --to sets every tagged page (bulk)', () async {
      hab.seed('/hq/cto', 'a',
          '---\ntype: semantic\nattention: 0.8\ntags: [front]\n---\n\na\n');
      hab.seed('/hq/cto', 'b',
          '---\ntype: semantic\nattention: 0.5\ntags: [front]\n---\n\nb\n');
      final (out, _, code) = await run(['refocus', '-p', '/hq/cto', '--tag', 'front', '--to', '0.2']);
      expect(code, 0);
      expect(page('/hq/cto', 'a').fields.attention.render(), '0.2');
      expect(page('/hq/cto', 'b').fields.attention.render(), '0.2');
      expect(out, contains('refocused 2 pages  (tag:front)'));
    });

    test('--by shifts relatively and clamps at the rail, visibly', () async {
      hab.seed('/hq/cto', 'a',
          '---\ntype: semantic\nattention: 0.3\ntags: [front]\n---\n\na\n');
      final (out, _, code) = await run(['refocus', '-p', '/hq/cto', '--tag', 'front', '--by', '-0.4']);
      expect(code, 0);
      expect(page('/hq/cto', 'a').fields.attention.render(), '0.0');
      expect(out, contains('0.3 → 0.0'));
      expect(out, contains('(clamped)'));
    });

    test('an empty selection is a clean no-op, not an error', () async {
      final (out, _, code) = await run(['refocus', '-p', '/hq/cto', '--tag', 'ghost', '--to', '0.2']);
      expect(code, 0);
      expect(out, contains('no pages matched'));
    });

    test('exactly one of --to / --by is required', () async {
      final (_, err, code) = await run(['refocus', '-p', '/hq/cto', 'front']);
      expect(code, 1);
      expect(err, contains('exactly one'));
    });
  });
}
