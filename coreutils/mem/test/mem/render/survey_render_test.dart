import 'package:mem/src/mem/model/mem_node.dart';
import 'package:mem/src/mem/render/survey_render.dart';
import 'package:mem/src/mem/word_count.dart';
import 'package:test/test.dart';

MemPage pg(MemPageType type, String name, {double weight = 0.8, String? gist}) =>
    MemPage(type: type, target: '$name.md', weight: weight);

void main() {
  // Threshold of 5 words keeps tests readable.
  final render = SurveyRender(wordCount: const WordCount(threshold: 5));

  group('SurveyRender', () {
    test('mode label prints once per group, not per row', () {
      final pages = [
        pg(MemPageType.episodic, 'ep-a'),
        pg(MemPageType.episodic, 'ep-b'),
      ];
      final result = render.render(pages);
      expect('episodic'.allMatches(result).length, 1,
          reason: 'group label appears once');
    });

    test('line shape contains weight and name', () {
      final pages = [pg(MemPageType.semantic, 'my-concept', weight: 0.7)];
      final result = render.render(pages);
      expect(result, contains('my-concept'));
      expect(result, contains('0.7'));
    });

    test('line contains gist when body has frontmatter gist', () {
      final pages = [pg(MemPageType.semantic, 'my-concept')];
      final result = render.render(pages, bodies: {
        'my-concept': '---\ngist: a clear summary\n---\nbody text',
      });
      // Shape: "weight  name — gist"
      expect(result, contains('—'));
      expect(result, contains('a clear summary'));
    });

    test('size hint absent when body is short', () {
      final pages = [pg(MemPageType.semantic, 'short-page')];
      final result = render.render(pages,
          bodies: {'short-page': 'few words'});
      expect(result, isNot(matches(r'\[\d+w\]')));
    });

    test('size hint present when body meets threshold', () {
      // threshold = 5 words in this test suite's SurveyRender instance.
      final pages = [pg(MemPageType.semantic, 'long-page')];
      final result = render.render(pages, bodies: {
        'long-page': 'one two three four five six',
      });
      expect(result, matches(r'\[\d+w\]'));
    });

    test('groups appear in composition order', () {
      final pages = [
        pg(MemPageType.prospective, 'intent-a'),
        pg(MemPageType.semantic, 'sem-a'),
        pg(MemPageType.autobiographical, 'arc-a'),
        pg(MemPageType.episodic, 'ep-a'),
        pg(MemPageType.procedural, 'craft-a'),
      ];
      final result = render.render(pages);
      final autoIdx = result.indexOf('autobiographical');
      final epiIdx = result.indexOf('episodic');
      final semIdx = result.indexOf('semantic');
      final procIdx = result.indexOf('procedural');
      final prospIdx = result.indexOf('prospective');
      expect(autoIdx, lessThan(epiIdx));
      expect(epiIdx, lessThan(semIdx));
      expect(semIdx, lessThan(procIdx));
      expect(procIdx, lessThan(prospIdx));
    });

    test('affordance footer renders (mem recall <name>)', () {
      final pages = [pg(MemPageType.semantic, 'foo')];
      final result = render.render(pages);
      expect(result, contains('mem recall'));
    });

    test('empty pages returns begin-one guidance message', () {
      final result = render.render([]);
      // Guidance must mention how to create a first page.
      expect(result, contains('remember'));
    });
  });
}
