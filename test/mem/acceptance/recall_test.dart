import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('acceptance: recall', () {
    test('recall <name> prints one page in full under its rule', () async {
      final fs = seedFs(
        pages: {MemPageType.semantic: {'concept-x': 0.8}},
        content: {
          'concept-x': '---\ntelos: To explain X\ngist: X maps inputs to outputs\n---\nThe full body of concept X.\n',
        },
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'recall', 'concept-x'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('concept-x'));
      expect(r.out, contains('To explain X')); // telos shown
      expect(r.out, contains('The full body of concept X.')); // body shown
      expect(r.out, matches(r'[-─]{3,}'), reason: 'separator rule must appear');
    });

    test('recall a b prints both pages, separated', () async {
      final fs = seedFs(
        pages: {
          MemPageType.semantic: {'page-a': 0.8, 'page-b': 0.7},
        },
        content: {
          'page-a': '---\ntelos: Telos of A\n---\nBody of A.\n',
          'page-b': '---\ntelos: Telos of B\n---\nBody of B.\n',
        },
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'recall', 'page-a', 'page-b'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('page-a'));
      expect(r.out, contains('page-b'));
      expect(r.out, contains('Body of A.'));
      expect(r.out, contains('Body of B.'));
      final rulePattern = RegExp(r'[-─]{3,}');
      expect(rulePattern.allMatches(r.out).length, greaterThanOrEqualTo(2),
          reason: 'two pages must produce at least two rules');
    });

    test('recall --min-weight 1.0 pulls the full bodies of the 1.0 band', () async {
      final fs = seedFs(
        pages: {
          MemPageType.semantic: {'spine-a': 1.0, 'spine-b': 1.0, 'warm': 0.8},
        },
        content: {
          'spine-a': '---\ntelos: Telos A\n---\nSpine body A.\n',
          'spine-b': '---\ntelos: Telos B\n---\nSpine body B.\n',
          'warm': '---\ntelos: Telos Warm\n---\nWarm body.\n',
        },
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'recall', '--min-weight', '1.0'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('Spine body A.'));
      expect(r.out, contains('Spine body B.'));
      expect(r.out, isNot(contains('Warm body.')));
    });

    test('unknown name errors cleanly with non-zero exit and informative message',
        () async {
      final fs = seedFs(pages: {MemPageType.semantic: {'real-page': 0.8}});

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'recall', 'nonexistent-page'],
          fs: fs);
      expect(r.exitCode, isNot(0));
      expect(r.err, isNot(contains('UnimplementedError')),
          reason: 'error must be user-facing, not a stack trace');
    });

    test('a predicate and a name together: name page appears in output', () async {
      // recall <name> --min-weight: name-based selection takes precedence or
      // the named page satisfies both; the page must appear in output.
      final fs = seedFs(
        pages: {MemPageType.semantic: {'concept-x': 0.9}},
        content: {
          'concept-x': '---\ntelos: Telos of X\n---\nBody of concept X.\n',
        },
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'recall', '--min-weight', '0.5', 'concept-x'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('concept-x'));
      expect(r.out, contains('Body of concept X.'));
    });
  });
}
