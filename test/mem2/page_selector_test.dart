import 'package:bentos_userland/src/mem2/model/attention.dart';
import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/page_selector.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PageSelector — the shared reach', () {
    const sel = PageSelector();

    final pages = [
      memPage('proc', type: MemType.procedural, attention: '0.7', tags: ['a']),
      memPage('sem', type: MemType.semantic, attention: '0.4', tags: ['a', 'b']),
      memPage('auto', type: MemType.autobiographical, attention: '1.0'),
      memPage('pros', type: MemType.prospective, attention: '0.2', tags: ['b']),
    ];

    Attention at(String s) => Attention.parse(s);

    test('minAttention includes the boundary (>=)', () {
      final got = sel.select(pages, minAttention: at('0.7')).map((p) => p.topic);
      expect(got, containsAll(['proc', 'auto']));
      expect(got, isNot(contains('sem')));
    });

    test('maxAttention includes its boundary (<=)', () {
      final got = sel.select(pages, maxAttention: at('0.4')).map((p) => p.topic);
      expect(got, containsAll(['sem', 'pros']));
      expect(got, isNot(contains('proc')));
    });

    test('a band range intersects (via bounds)', () {
      final got = sel
          .select(pages, minAttention: at('0.7'), maxAttention: at('0.9'))
          .map((p) => p.topic);
      expect(got, ['proc'], reason: 'warm band [0.7,0.9]');
    });

    test('type narrows to one mode', () {
      expect(sel.select(pages, type: MemType.semantic).map((p) => p.topic),
          ['sem']);
    });

    test('tag narrows to carriers', () {
      expect(sel.select(pages, tag: 'b').map((p) => p.topic).toSet(),
          {'sem', 'pros'});
    });

    test('predicates compose as AND', () {
      final got = sel
          .select(pages, tag: 'a', minAttention: at('0.5'))
          .map((p) => p.topic);
      expect(got, ['proc'], reason: 'tag a AND >=0.5');
    });

    test('output stays in composition order', () {
      expect(sel.select(pages).map((p) => p.topic),
          ['auto', 'sem', 'proc', 'pros']);
    });

    test('empty result is empty, not error', () {
      expect(sel.select(pages, minAttention: at('1.0'), type: MemType.prospective),
          isEmpty);
    });
  });
}
