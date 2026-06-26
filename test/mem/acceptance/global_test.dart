import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('acceptance: global options', () {
    test('-a/--agent targets another agent\'s memory', () async {
      // Seed two agents at the same place; -a selects the right one.
      final fs = seedFs(
        agent: 'alfred',
        pages: {MemPageType.semantic: {'alfred-page': 0.8}},
        content: {'alfred-page': 'Alfred\'s page'},
      );
      // Also seed tester (the default) with a different page.
      final agentDir = '$kPlace/.mem/$kAgent';
      fs.directory(agentDir).createSync(recursive: true);
      fs.file('$agentDir/mem.yml').writeAsStringSync('''
agent: $kAgent
scope: test
edges:
  episodic: []
  semantic:
    - tester-page.md: 0.8
  prospective: []
  procedural: []
  autobiographical: []
''');
      fs.file('$agentDir/tester-page.md').writeAsStringSync('Tester\'s page');

      final r = await runMem(
          ['-a', 'alfred', '-p', kPlace, 'survey'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('alfred-page'));
      expect(r.out, isNot(contains('tester-page')));
    });

    test('-p/--place overrides the place', () async {
      // Seed memory at an alternative place.
      const altPlace = '/alt-place';
      final fs = seedFs(
        place: altPlace,
        pages: {MemPageType.semantic: {'alt-page': 0.8}},
        content: {'alt-page': 'alt body'},
      );

      final r = await runMem(
          ['-a', kAgent, '-p', altPlace, 'survey'],
          fs: fs);
      expect(r.exitCode, 0);
      expect(r.out, contains('alt-page'));
    });

    test('absent agent with no \$BENTOS_AGENT errors with guidance', () async {
      // When no -a flag AND no BENTOS_AGENT env var, the runner must error
      // with a helpful message telling the user how to specify an agent.
      // (This test assumes BENTOS_AGENT is not set in the test environment.)
      final fs = seedFs();

      final r = await runMem(['-p', kPlace, 'survey'], fs: fs);
      expect(r.exitCode, isNot(0));
      // Must mention how to specify an agent.
      expect(r.err, anyOf(contains('BENTOS_AGENT'), contains('--agent'), contains('-a')));
    });
  });
}
