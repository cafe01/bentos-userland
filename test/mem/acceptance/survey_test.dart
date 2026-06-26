import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('acceptance: survey', () {
    test('no predicate lists the whole index, grouped by mode', () async {
      final fs = seedFs(pages: {
        MemPageType.episodic: {'ep-a': 0.8, 'ep-b': 0.5},
        MemPageType.semantic: {'sem-a': 0.7},
        MemPageType.prospective: {'intent-a': 0.9},
      }, content: {
        'ep-a': 'body a',
        'ep-b': 'body b',
        'sem-a': 'body sem',
        'intent-a': 'body intent',
      });

      final r = await runMem(['-a', kAgent, '-p', kPlace, 'survey'], fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('episodic'));
      expect(r.out, contains('semantic'));
      expect(r.out, contains('prospective'));
      expect(r.out, contains('ep-a'));
      expect(r.out, contains('sem-a'));
    });

    test('--min-weight 0.7 drops everything below', () async {
      final fs = seedFs(pages: {
        MemPageType.episodic: {'hot': 0.9, 'warm': 0.7, 'cold': 0.4},
      }, content: {
        'hot': 'body hot',
        'warm': 'body warm',
        'cold': 'body cold',
      });

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'survey', '--min-weight', '0.7'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('hot'));
      expect(r.out, contains('warm'));
      expect(r.out, isNot(contains('cold')));
    });

    test('--max-weight selects correctly', () async {
      final fs = seedFs(pages: {
        MemPageType.semantic: {'high': 0.9, 'mid': 0.6, 'low': 0.3},
      }, content: {
        'high': 'body',
        'mid': 'body',
        'low': 'body',
      });

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'survey', '--max-weight', '0.6'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, isNot(contains('high')));
      expect(r.out, contains('mid'));
      expect(r.out, contains('low'));
    });

    test('band (--min-weight + --max-weight) selects correctly', () async {
      final fs = seedFs(pages: {
        MemPageType.prospective: {'high-x': 0.9, 'mid-x': 0.6, 'low-x': 0.3},
      }, content: {'high-x': 'body', 'mid-x': 'body', 'low-x': 'body'});

      final r = await runMem([
        '-a', kAgent, '-p', kPlace,
        'survey', '--min-weight', '0.5', '--max-weight', '0.8',
      ], fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, isNot(contains('high-x'))); // 0.9 > band
      expect(r.out, contains('mid-x')); // 0.6 in band
      expect(r.out, isNot(contains('low-x'))); // 0.3 < band
    });

    test('--type semantic shows only semantic pages', () async {
      final fs = seedFs(pages: {
        MemPageType.semantic: {'sem-page': 0.8},
        MemPageType.episodic: {'ep-page': 0.8},
      }, content: {'sem-page': 'body', 'ep-page': 'body'});

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'survey', '--type', 'semantic'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('sem-page'));
      expect(r.out, isNot(contains('ep-page')));
    });

    test('--tag filters to pages carrying that tag', () async {
      final fs = seedFs(
        pages: {
          MemPageType.episodic: {'tagged-ep': 0.8, 'plain-ep': 0.8},
        },
        content: {
          'tagged-ep': '---\ntags:\n  - kernel\n---\nbody',
          'plain-ep': 'no tags here',
        },
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'survey', '--tag', 'kernel'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('tagged-ep'));
      expect(r.out, isNot(contains('plain-ep')));
    });

    test('--min-weight 1.0 shows only the trust-read tier', () async {
      final fs = seedFs(pages: {
        MemPageType.semantic: {'spine': 1.0, 'warm': 0.8},
      }, content: {'spine': 'body', 'warm': 'body'});

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'survey', '--min-weight', '1.0'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('spine'));
      expect(r.out, isNot(contains('warm')));
    });
  });
}
