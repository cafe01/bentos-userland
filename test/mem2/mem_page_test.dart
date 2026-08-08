import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:test/test.dart';

void main() {
  group('MemPage / frontmatter round-trip', () {
    const content = '---\n'
        'type: semantic\n'
        'attention: 0.7\n'
        'tags: [founders, working-model]\n'
        'created: 2026-07-01T09:00:00.000Z\n'
        'modified: 2026-07-02T10:00:00.000Z\n'
        'gist: who the founders are\n'
        '---\n'
        '\n'
        'The founders — Cafe and Alfred.\n';

    test('round-trips every field + body', () {
      final page = MemPage.parse('founders', content);
      expect(page.topic, 'founders');
      expect(page.fields.type, MemType.semantic);
      expect(page.fields.attention, Attention.parse('0.7'));
      expect(page.fields.tags, ['founders', 'working-model']);
      expect(page.fields.created, DateTime.utc(2026, 7, 1, 9));
      expect(page.fields.modified, DateTime.utc(2026, 7, 2, 10));
      expect(page.fields.gist, 'who the founders are');
      expect(page.body, 'The founders — Cafe and Alfred.');
    });

    test('serialize → parse is stable', () {
      final page = MemPage.parse('founders', content);
      final reparsed = MemPage.parse('founders', page.serialize());
      expect(reparsed.fields.type, page.fields.type);
      expect(reparsed.fields.attention, page.fields.attention);
      expect(reparsed.fields.tags, page.fields.tags);
      expect(reparsed.fields.gist, page.fields.gist);
      expect(reparsed.body, page.body);
    });

    test('missing required type degrades, never throws', () {
      final page = MemPage.parse('x', '---\nattention: 0.5\n---\nbody\n');
      expect(page.fields.type, MemType.semantic);
      expect(page.fields.attention, Attention.parse('0.5'));
      expect(page.body, 'body');
      expect(page.isDegraded, isTrue);
      expect(page.fields.assumptions.single.field, 'type');
    });

    test('missing frontmatter degrades to a bodyless-header page', () {
      final page = MemPage.parse('x', 'just a body');
      expect(page.body, 'just a body');
      expect(page.fields.type, MemType.semantic);
      expect(page.fields.attention, Attention.assumedDefault);
      expect(page.isDegraded, isTrue);
      expect(page.fields.assumptions.single.field, 'frontmatter');
    });

    test('unterminated frontmatter degrades, entire content kept as body', () {
      final page = MemPage.parse('x', '---\ntype: semantic\nattention: 0.5\nno close fence');
      expect(page.isDegraded, isTrue);
      expect(page.body, contains('no close fence'));
    });

    test('unparseable YAML frontmatter degrades but keeps the real body', () {
      final page = MemPage.parse('x', '---\n[unterminated: [\n---\n\nreal body\n');
      expect(page.isDegraded, isTrue);
      expect(page.fields.type, MemType.semantic);
      expect(page.body, 'real body');
    });

    test('off-notch attention degrades that one field only', () {
      final page = MemPage.parse(
        'x',
        '---\ntype: procedural\nattention: 0.75\n---\nbody\n',
      );
      expect(page.fields.type, MemType.procedural, reason: 'type was legible');
      expect(page.fields.attention, Attention.assumedDefault);
      expect(page.fields.assumptions.single.field, 'attention');
    });

    test('type is case- and whitespace-insensitive', () {
      final page = MemPage.parse('x', '---\ntype:  Semantic \nattention: 0.5\n---\nbody\n');
      expect(page.fields.type, MemType.semantic);
      expect(page.isDegraded, isFalse);
    });

    test('attention accepts the wider on-disk grammar without degrading', () {
      for (final form in ['1', '.7', '0.70', '"0.7"', ' 0.7 ']) {
        final page = MemPage.parse('x', '---\ntype: semantic\nattention: $form\n---\nbody\n');
        expect(page.isDegraded, isFalse, reason: 'form: $form');
      }
      expect(
        MemPage.parse('x', '---\ntype: semantic\nattention: 1\n---\nbody\n').fields.attention,
        Attention.parse('1.0'),
      );
    });

    test('a bare-scalar tags line is one tag, not zero', () {
      final page = MemPage.parse('x', '---\ntype: semantic\nattention: 0.5\ntags: solo\n---\nbody\n');
      expect(page.fields.tags, ['solo']);
    });

    test('an unparseable date is dropped, not thrown', () {
      final page = MemPage.parse(
        'x',
        '---\ntype: semantic\nattention: 0.5\ncreated: not-a-date\n---\nbody\n',
      );
      expect(page.fields.created, isNull);
      expect(page.isDegraded, isTrue);
      expect(page.fields.assumptions.single.field, 'created');
    });

    test('a gist opening on a YAML indicator survives the round trip', () {
      const gist = '**diary** — the archive organ, with a "quote" and a \\ slash';
      final page = MemPage.parse('x', '---\ntype: procedural\nattention: 0.5\n---\nbody\n')
          .fields
          .copyWith(gist: gist);
      final reparsed = MemPage.parse('x', '${page.serialize()}\n\nbody\n');
      expect(reparsed.fields.gist, gist);
    });

    test('a gist is quoted unconditionally, even when it is innocent', () {
      final page = MemPage.parse('x', '---\ntype: semantic\nattention: 0.5\n---\nbody\n')
          .fields
          .copyWith(gist: 'plain prose with nothing dangerous in it');
      expect(page.serialize(),
          contains('gist: "plain prose with nothing dangerous in it"'),
          reason: 'no predicate decides per value whether YAML can be trusted');
    });

    test('unknown keys are preserved (OKF augmentation)', () {
      const augmented = '---\ntype: episodic\nattention: 0.3\nsource: cafe\n---\nbody\n';
      final page = MemPage.parse('x', augmented);
      expect(page.fields.extras['source'], 'cafe');
      expect(page.serialize(), contains('source: cafe'));
    });
  });
}
