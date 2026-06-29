import 'package:file/memory.dart';
import 'package:bentos_userland/src/manifest/tree_lister.dart';
import 'package:test/test.dart';

void _seed(MemoryFileSystem fs, String path, String content) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  group('fqdnMatchesGlob — pure, dot-segment semantics', () {
    test('exact, no wildcard', () {
      expect(fqdnMatchesGlob('alfred.soul', 'alfred.soul'), isTrue);
      expect(fqdnMatchesGlob('alfred.soul', 'soul'), isFalse);
    });

    test('* matches WITHIN a single segment, not across', () {
      expect(fqdnMatchesGlob('alfred.soul', '*.soul'), isTrue);
      // '*.soul' is two segments; a three-segment fqdn must not match.
      expect(fqdnMatchesGlob('a.b.soul', '*.soul'), isFalse);
    });

    test('** matches ACROSS any number of segments', () {
      expect(fqdnMatchesGlob('swift.coding.craft.skill', '**.skill'), isTrue);
      expect(fqdnMatchesGlob('x.skill', '**.skill'), isTrue);
    });

    test('a family glob excludes other families', () {
      expect(fqdnMatchesGlob('alfred.soul', '**.skill'), isFalse);
    });
  });

  group('TreeLister.list — walk, map back to FQDN, filter', () {
    late MemoryFileSystem fs;
    late TreeLister lister;

    setUp(() {
      fs = MemoryFileSystem();
      _seed(fs, '/tree/soul/alfred/alfred.xml', '<atom/>');
      _seed(fs, '/tree/faculty/anamnesis/anamnesis.xml', '<atom/>');
      _seed(fs, '/tree/skill/craft/coding/dart/dart.xml', '<atom/>');
      // A member file (basename ≠ dir) — an xi:include part, NOT a particle root.
      _seed(fs, '/tree/skill/craft/coding/dart/skill_abstract.xml', '<x/>');
      // A deep particle (named convention) plus a stray atom.xml that must be ignored.
      _seed(fs, '/tree/skill/tools/git/git.xml', '<atom/>');
      _seed(fs, '/tree/skill/tools/git/atom.xml', '<atom/>');
      lister = TreeLister(fs, const ['/tree']);
    });

    test('lists every particle FQDN, sorted, members excluded', () {
      expect(lister.list('**'), [
        'alfred.soul',
        'anamnesis.faculty',
        'dart.coding.craft.skill',
        'git.tools.skill',
      ]);
    });

    test('a deep named particle appears; a sibling atom.xml is ignored', () {
      expect(lister.list('**.skill'), contains('git.tools.skill'));
    });

    test('a member file never appears as a particle', () {
      // skill_abstract.xml would map to a non-root → must be absent everywhere.
      expect(
        lister.list('**').any((f) => f.contains('abstract')),
        isFalse,
      );
    });

    test('glob filters by family', () {
      expect(lister.list('*.soul'), ['alfred.soul']);
      expect(lister.list('**.skill'), [
        'dart.coding.craft.skill',
        'git.tools.skill',
      ]);
    });
  });

  group('TreeLister.list — union across roots', () {
    test('a particle present in two roots lists exactly once', () {
      final fs = MemoryFileSystem();
      _seed(fs, '/a/soul/alfred/alfred.xml', '<atom/>');
      _seed(fs, '/b/soul/alfred/alfred.xml', '<atom/>');
      final lister = TreeLister(fs, const ['/a', '/b']);
      expect(lister.list('**'), ['alfred.soul']);
    });
  });
}
