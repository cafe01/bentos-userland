import 'package:bentos_userland/src/mem2/gist_deriver.dart';
import 'package:test/test.dart';

void main() {
  group('GistDeriver', () {
    test('with --gist set, returns it verbatim and does not call llm', () async {
      var calls = 0;
      final deriver = GistDeriver((body) async {
        calls++;
        return 'derived';
      });

      final gist = await deriver.derive('a body', manualGist: 'hand-written');

      expect(gist, 'hand-written', reason: 'manual override wins verbatim');
      expect(calls, 0, reason: 'the llm seam is never touched when --gist is given');
    });

    test('without --gist, calls the llm seam and returns its single line', () async {
      String? seen;
      final deriver = GistDeriver((body) async {
        seen = body;
        return 'what you will find if you open this page';
      });

      final gist = await deriver.derive('the page body');

      expect(seen, 'the page body', reason: 'the body is what gets piped');
      expect(gist, 'what you will find if you open this page');
    });

    test('collapses a multi-line answer to its first line, trimmed', () async {
      final deriver = GistDeriver((_) async => '  the navigation line  \nstray second line\n');

      expect(await deriver.derive('body'), 'the navigation line');
    });

    test('a derivation failure surfaces, never a silent empty gist', () async {
      final thrower = GistDeriver((_) async => throw Exception('llm exploded'));
      await expectLater(
        thrower.derive('body'),
        throwsA(isA<GistDerivationFailed>()),
        reason: 'a thrown seam surfaces, does not swallow to empty',
      );

      final empty = GistDeriver((_) async => '   \n  ');
      await expectLater(
        empty.derive('body'),
        throwsA(isA<GistDerivationFailed>()),
        reason: 'an empty answer is a failure, not a silent empty gist',
      );
    });
  });
}
