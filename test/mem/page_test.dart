import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:test/test.dart';

void main() {
  group('Page / frontmatter round-trip', () {
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
      final page = Page.parse('founders', content);
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
      final page = Page.parse('founders', content);
      final reparsed = Page.parse('founders', page.serialize());
      expect(reparsed.fields.type, page.fields.type);
      expect(reparsed.fields.attention, page.fields.attention);
      expect(reparsed.fields.tags, page.fields.tags);
      expect(reparsed.fields.gist, page.fields.gist);
      expect(reparsed.body, page.body);
    });

    test('missing required type degrades, never throws', () {
      final page = Page.parse('x', '---\nattention: 0.5\n---\nbody\n');
      expect(page.fields.type, MemType.semantic);
      expect(page.fields.attention, Attention.parse('0.5'));
      expect(page.body, 'body');
      expect(page.isAssumed, isTrue);
      expect(page.fields.assumptions.single.field, 'type');
    });

    test('missing frontmatter degrades to a bodyless-header page', () {
      final page = Page.parse('x', 'just a body');
      expect(page.body, 'just a body');
      expect(page.fields.type, MemType.semantic);
      expect(page.fields.attention, Attention.assumedDefault);
      expect(page.isAssumed, isTrue);
      expect(page.fields.assumptions.single.field, 'frontmatter');
    });

    test('unterminated frontmatter degrades, entire content kept as body', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\nno close fence');
      expect(page.isAssumed, isTrue);
      expect(page.body, contains('no close fence'));
    });

    test('unparseable YAML frontmatter degrades but keeps the real body', () {
      final page = Page.parse('x', '---\n[unterminated: [\n---\n\nreal body\n');
      expect(page.isAssumed, isTrue);
      expect(page.fields.type, MemType.semantic);
      expect(page.body, 'real body');
    });

    test('off-notch attention degrades that one field only', () {
      final page = Page.parse('x', '---\ntype: procedural\nattention: 0.75\n---\nbody\n');
      expect(page.fields.type, MemType.procedural, reason: 'type was legible');
      expect(page.fields.attention, Attention.assumedDefault);
      expect(page.fields.assumptions.single.field, 'attention');
    });

    test('type is case- and whitespace-insensitive', () {
      final page = Page.parse('x', '---\ntype:  Semantic \nattention: 0.5\n---\nbody\n');
      expect(page.fields.type, MemType.semantic);
      expect(page.isAssumed, isFalse);
    });

    test('a bare-scalar tags line is one tag, not zero', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\ntags: solo\n---\nbody\n');
      expect(page.fields.tags, ['solo']);
    });

    test('an unparseable date is dropped, not thrown', () {
      final page = Page.parse(
        'x',
        '---\ntype: semantic\nattention: 0.5\ncreated: not-a-date\n---\nbody\n',
      );
      expect(page.fields.created, isNull);
      expect(page.isAssumed, isTrue);
      expect(page.fields.assumptions.single.field, 'created');
    });

    test('a gist is quoted unconditionally, even when it is innocent', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\nbody\n')
          .fields
          .copyWith(gist: 'plain prose with nothing dangerous in it');
      expect(page.serialize(), contains('gist: "plain prose with nothing dangerous in it"'),
          reason: 'no predicate decides per value whether YAML can be trusted');
    });

    test('a gist opening on a YAML indicator survives the round trip', () {
      const gist = '**diary** — the archive organ, with a "quote" and a \\ slash';
      final page = Page.parse('x', '---\ntype: procedural\nattention: 0.5\n---\nbody\n')
          .fields
          .copyWith(gist: gist);
      final reparsed = Page.parse('x', '${page.serialize()}\n\nbody\n');
      expect(reparsed.fields.gist, gist);
    });

    test('unknown keys are preserved (augmentation)', () {
      const augmented = '---\ntype: episodic\nattention: 0.3\nsource: cafe\n---\nbody\n';
      final page = Page.parse('x', augmented);
      expect(page.fields.extras['source'], 'cafe');
      expect(page.serialize(), contains('source: cafe'));
    });

    test('an assumption never round-trips into the serialized bytes', () {
      final degraded = Page.parse('x', 'no frontmatter at all, just prose');
      expect(degraded.isAssumed, isTrue);
      final bytes = degraded.serialize();
      expect(bytes, isNot(contains('assumption')));
      expect(bytes, isNot(contains('frontmatter:')));
      // Re-parsing the written bytes is a clean page: the guess was never
      // canonized as if it had been authored.
      expect(Page.parse('x', bytes).isAssumed, isFalse);
    });
  });

  group('Page.links — prose order, same-bank and cross-bank', () {
    test('reads same-bank and cross-bank links in appearance order', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\n'
          'See [[domain/bentos/brain]] and then '
          '[[mem://bentos-agent.mem/domain/bentos-agent/wake|the wake]], '
          'finally [[domain/bentos/actor|actors]].\n');
      final links = page.links;
      expect(links, hasLength(3));

      expect(links[0].bank, isNull);
      expect(links[0].topic, 'domain/bentos/brain');
      expect(links[0].text, isNull);
      expect(links[0].order, 0);

      expect(links[1].bank, 'bentos-agent.mem');
      expect(links[1].topic, 'domain/bentos-agent/wake');
      expect(links[1].text, 'the wake');
      expect(links[1].order, 1);

      expect(links[2].bank, isNull);
      expect(links[2].topic, 'domain/bentos/actor');
      expect(links[2].text, 'actors');
      expect(links[2].order, 2);
    });

    test('a page with no links returns an empty list', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\nplain prose\n');
      expect(page.links, isEmpty);
    });

    // The three offender shapes the real corpus produced: a link-shaped span
    // inside a fenced block, one inside inline code, and link-shaped text in
    // frontmatter. Prose-only parsing must see none of them.
    test('a wikilink inside a fenced code block is not a link', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\n'
          '```dart\n'
          '// see [[domain/bentos/brain]] for context\n'
          '```\n'
          'real prose has no link here.\n');
      expect(page.links, isEmpty);
    });

    test('a wikilink inside an inline code span is not a link', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\n'
          'the literal syntax `[[domain/bentos/brain]]` is documented here, '
          'not linked.\n');
      expect(page.links, isEmpty);
    });

    test('link-shaped text in frontmatter is not a link', () {
      // A model-derived gist can inject a bracketed span into frontmatter —
      // observed in the real corpus. Frontmatter is never body, so it never
      // reaches the link scan regardless of what it contains.
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n'
          'gist: "see [[domain/bentos/brain]] for more"\n'
          '---\nplain prose.\n');
      expect(page.links, isEmpty);
    });

    test('a fence reopens correctly after closing, prose links after it are read', () {
      final page = Page.parse('x', '---\ntype: semantic\nattention: 0.5\n---\n'
          '```\n[[not/a/link]]\n```\n'
          'but [[domain/bentos/brain|this one]] is real.\n');
      expect(page.links, hasLength(1));
      expect(page.links.single.topic, 'domain/bentos/brain');
    });
  });

  group('Selector — the shared reach', () {
    Page page(String topic, {required MemType type, required String attention, List<String> tags = const []}) =>
        Page(
          topic: topic,
          fields: Fields(type: type, attention: Attention.parse(attention), tags: tags),
          body: '',
        );

    final pages = [
      page('proc', type: MemType.procedural, attention: '0.7', tags: ['a']),
      page('sem', type: MemType.semantic, attention: '0.4', tags: ['a', 'b']),
      page('auto', type: MemType.autobiographical, attention: '1.0'),
      page('pros', type: MemType.prospective, attention: '0.2', tags: ['b']),
    ];

    Attention at(String s) => Attention.parse(s);

    test('minAttention includes the boundary (>=)', () {
      final hot = Selector(minAttention: at('0.7')).select(pages).map((p) => p.topic);
      expect(hot, containsAll(['proc', 'auto']));
      expect(hot, isNot(contains('sem')));
    });

    test('maxAttention includes its boundary (<=)', () {
      final got = Selector(maxAttention: at('0.4')).select(pages).map((p) => p.topic);
      expect(got, containsAll(['sem', 'pros']));
      expect(got, isNot(contains('proc')));
    });

    test('type narrows to one mode', () {
      expect(Selector(type: MemType.semantic).select(pages).map((p) => p.topic), ['sem']);
    });

    test('tag narrows to carriers', () {
      expect(Selector(tag: 'b').select(pages).map((p) => p.topic).toSet(), {'sem', 'pros'});
    });

    test('topic narrows to one page', () {
      expect(Selector(topic: 'auto').select(pages).map((p) => p.topic), ['auto']);
    });

    test('predicates compose as AND', () {
      final got = Selector(tag: 'a', minAttention: at('0.5')).select(pages).map((p) => p.topic);
      expect(got, ['proc'], reason: 'tag a AND >=0.5');
    });

    test('output is hottest first, ties broken by topic', () {
      expect(const Selector().select(pages).map((p) => p.topic), ['auto', 'proc', 'sem', 'pros']);
    });

    test('a tie in attention breaks by topic', () {
      final tied = [
        page('zzz', type: MemType.semantic, attention: '0.7'),
        page('aaa', type: MemType.procedural, attention: '0.7'),
      ];
      expect(const Selector().select(tied).map((p) => p.topic), ['aaa', 'zzz']);
    });

    test('empty result is empty, not error', () {
      expect(Selector(minAttention: at('1.0'), type: MemType.prospective).select(pages), isEmpty);
    });

    test('matches() is the same predicate select() filters by', () {
      const sel = Selector(tag: 'a');
      for (final p in pages) {
        expect(sel.select(pages).contains(p), sel.matches(p));
      }
    });
  });
}
