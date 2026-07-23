import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/relative_age.dart';
import 'package:bentos_userland/src/mem2/render/recall_render.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RecallRender — deliberate retrieval', () {
    final clock = DateTime.utc(2026, 7, 2, 12);
    final render = RecallRender(RelativeAge(() => clock));

    test('a single page: rule + title (topic · mode · attention · words · age) + body', () {
      final out = render.render([
        memPage('agency/fetch-reflex',
            type: MemType.procedural,
            attention: '0.7',
            body: 'The underdeveloped keystone.',
            modified: clock.subtract(const Duration(days: 5))),
      ]);
      expect(out, contains('agency/fetch-reflex  ·  procedural  ·  a:0.7  ·  3 words  ·  modified 5d ago'));
      expect(out, contains('The underdeveloped keystone.'));
      expect('─'.allMatches(out).isNotEmpty, isTrue);
    });

    test('the weight names its unit — a bare magnitude is not a measurement', () {
      final out = render.render([memPage('a', body: 'one two three four')]);
      expect(out, contains('4 words'));
      expect(out, isNot(contains('4w')));
    });

    test('N pages render N separator rules, unambiguous at the seams', () {
      final out = render.render([
        memPage('a', body: 'first'),
        memPage('b', body: 'second'),
      ]);
      final rules = RegExp('^─+\$', multiLine: true).allMatches(out);
      expect(rules, hasLength(2));
      expect(out.indexOf('first'), lessThan(out.indexOf('second')));
    });

    test('no raw frontmatter leaks into the render', () {
      final out = render.render([memPage('a', attention: '0.5', body: 'body')]);
      expect(out, isNot(contains('---')));
      expect(out, isNot(contains('type:')));
    });

    test('a missing body renders the title honestly, does not crash', () {
      final out = render.render([memPage('a', body: '')]);
      expect(out, contains('a  ·  semantic'));
    });
  });
}
