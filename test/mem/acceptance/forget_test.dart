import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('acceptance: forget', () {
    test('forget removes the page and deletes its content file', () async {
      final fs = seedFs(
        pages: {MemPageType.episodic: {'old-memory': 0.6}},
        content: {'old-memory': 'body to delete'},
      );

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'forget', 'old-memory'],
          fs: fs);
      expect(r.exitCode, 0);

      final node = MemResolver(agent: kAgent, fileSystem: fs).resolve(kPlace)!;
      expect(
        node.pagesOf(MemPageType.episodic).any((pg) => pg.name == 'old-memory'),
        isFalse,
        reason: 'page must be removed from mem.yml',
      );
      expect(
        fs.file(p.join(kPlace, '.mem', kAgent, 'old-memory.md')).existsSync(),
        isFalse,
        reason: 'content file must be deleted',
      );
    });

    test('unknown name errors cleanly', () async {
      final fs = seedFs();

      final r = await runMem(
          ['-a', kAgent, '-p', kPlace, 'forget', 'nonexistent-page'],
          fs: fs);
      expect(r.exitCode, isNot(0));
      expect(r.err, isNot(contains('UnimplementedError')),
          reason: 'error must be user-facing');
    });
  });
}
