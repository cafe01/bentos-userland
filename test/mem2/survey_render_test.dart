import 'package:bentos_userland/src/mem2/model/mem_page.dart';
import 'package:bentos_userland/src/mem2/relative_age.dart';
import 'package:bentos_userland/src/mem2/render/survey_render.dart';
import 'package:bentos_userland/src/mem2/word_count.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('SurveyRender — the memory map', () {
    final clock = DateTime.utc(2026, 7, 2, 12);
    final render = SurveyRender(
      age: RelativeAge(() => clock),
      wordCount: const WordCount(threshold: 3),
    );

    test('mode label prints once per group, in composition order', () {
      runInMemoryFs((fs) {
        MemHabitat()..place('/hq')..place('/hq/cto');
        final vantage = Place('/hq/cto');
        final out = render.render([
          memPage('auto', type: MemType.autobiographical, attention: '1.0', origin: vantage),
          memPage('s1', type: MemType.semantic, attention: '0.8', origin: vantage),
          memPage('s2', type: MemType.semantic, attention: '0.7', origin: vantage),
        ], vantage: vantage);
        final lines = out.split('\n');
        expect(lines[0], 'autobiographical');
        expect(lines[2], 'semantic');
        expect('semantic'.allMatches(out), hasLength(1));
        expect(lines.indexOf('autobiographical'),
            lessThan(lines.indexOf('semantic')));
      });
    });

    test('line shape: attention  topic — gist, then the trailing cluster', () {
      runInMemoryFs((fs) {
        MemHabitat()..place('/hq')..place('/hq/cto');
        final vantage = Place('/hq/cto');
        final out = render.render([
          memPage('cafe/as-partner',
              attention: '0.8',
              gist: 'creator/CTO/co-founder',
              tags: ['x'],
              body: 'a b c d',
              modified: clock.subtract(const Duration(hours: 2)),
              origin: vantage),
        ], vantage: vantage);
        expect(out, contains('  0.8  cafe/as-partner — creator/CTO/co-founder  #x  ·2h  [4w]'));
      });
    });

    test('@place marks only inherited pages', () {
      runInMemoryFs((fs) {
        MemHabitat()..place('/hq')..place('/hq/cto');
        final vantage = Place('/hq/cto');
        final ancestor = Place('/hq');
        final out = render.render([
          memPage('local', attention: '0.8', origin: vantage),
          memPage('inherited', attention: '0.8', origin: ancestor),
        ], vantage: vantage);
        expect(out, contains('  0.8  local\n'), reason: 'local has no @place');
        expect(out, contains('  0.8  inherited  @${ancestor.name}'));
      });
    });

    test('size hint only above threshold', () {
      runInMemoryFs((fs) {
        MemHabitat()..place('/hq')..place('/hq/cto');
        final vantage = Place('/hq/cto');
        final out = render.render([
          memPage('short', attention: '0.5', body: 'a b', origin: vantage),
        ], vantage: vantage);
        expect(out, isNot(contains('[')));
      });
    });

    test('the affordance footer trails the map', () {
      runInMemoryFs((fs) {
        MemHabitat()..place('/hq')..place('/hq/cto');
        final vantage = Place('/hq/cto');
        final out = render.render(
            [memPage('x', attention: '0.5', origin: vantage)], vantage: vantage);
        expect(out.trimRight(), endsWith(SurveyRender.footer));
      });
    });
  });
}
