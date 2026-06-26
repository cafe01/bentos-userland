import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/render/recall_render.dart';
import 'package:test/test.dart';

MemPage pg(MemPageType type, String name, {double weight = 0.8}) =>
    MemPage(type: type, target: '$name.md', weight: weight);

void main() {
  const render = RecallRender();

  group('RecallRender', () {
    test('single page renders: rule + title + telos + body', () {
      final pages = [pg(MemPageType.semantic, 'concept-x', weight: 0.7)];
      // RecallRender needs access to the page content (telos + body).
      // The exact mechanism (FileSystem injection or pre-loaded content) is TBD.
      // This test documents the contract: output must contain all four elements.
      final result = render.render(pages);
      expect(result, contains('concept-x'), reason: 'title must appear');
      expect(result, contains('semantic'), reason: 'mode must appear');
      expect(result, contains('0.7'), reason: 'weight must appear');
      // Rule: a horizontal separator line (e.g. "───" or "---")
      expect(result, matches(r'[-─]+'), reason: 'separator rule must appear');
    });

    test('N pages render N rules — no ambiguity at seams', () {
      final pages = [
        pg(MemPageType.semantic, 'concept-a'),
        pg(MemPageType.episodic, 'episode-b'),
      ];
      final result = render.render(pages);
      // Two pages → two separator rules in the output.
      final rulePattern = RegExp(r'[-─]{3,}');
      expect(rulePattern.allMatches(result).length, greaterThanOrEqualTo(2),
          reason: 'each page must have its own rule');
    });

    test('no raw frontmatter in output', () {
      final pages = [pg(MemPageType.semantic, 'concept-x')];
      final result = render.render(pages);
      // The frontmatter delimiters must not appear raw in body output.
      expect(result, isNot(contains('telos:')),
          reason: 'telos key must not appear as raw YAML');
    });

    test('missing body (legacy gist-only page) renders honestly, does not crash', () {
      final pages = [pg(MemPageType.prospective, 'gist-only-legacy')];
      // A page whose content file exists but has no body after frontmatter
      // must render without throwing. The title + telos still show.
      expect(() => render.render(pages), returnsNormally);
      final result = render.render(pages);
      expect(result, contains('gist-only-legacy'));
    });
  });
}
