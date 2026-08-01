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

    test('missing required type errors', () {
      expect(
        () => MemPage.parse('x', '---\nattention: 0.5\n---\nbody\n'),
        throwsFormatException,
      );
    });

    test('missing frontmatter errors', () {
      expect(() => MemPage.parse('x', 'just a body'), throwsFormatException);
    });

    test('a gist opening on a YAML indicator survives the round trip', () {
      const gist = '**diary** — the archive organ, with a "quote" and a \\ slash';
      final page = MemPage.parse('x', '---\ntype: procedural\nattention: 0.5\n---\nbody\n')
          .fields
          .copyWith(gist: gist);
      final reparsed = MemPage.parse('x', '${page.serialize()}\n\nbody\n');
      expect(reparsed.fields.gist, gist);
    });

    test('unknown keys are preserved (OKF augmentation)', () {
      const augmented = '---\ntype: episodic\nattention: 0.3\nsource: cafe\n---\nbody\n';
      final page = MemPage.parse('x', augmented);
      expect(page.fields.extras['source'], 'cafe');
      expect(page.serialize(), contains('source: cafe'));
    });
  });
}
