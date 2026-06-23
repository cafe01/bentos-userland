import 'package:file/memory.dart';
import 'package:bentos_userland/src/manifest/path_resolver.dart';
import 'package:test/test.dart';

/// Seed a particle file at [path] with marker [content] in [fs].
void _seed(MemoryFileSystem fs, String path, String content) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  group('fqdnToRelPath — uniform reverse, file = <first-segment>.xml', () {
    final r = PathResolver(MemoryFileSystem(), const []);

    test('two segments (soul)', () {
      expect(r.fqdnToRelPath('alfred.soul'), 'soul/alfred/alfred.xml');
    });

    test('two segments (faculty)', () {
      expect(
        r.fqdnToRelPath('anamnesis.faculty'),
        'faculty/anamnesis/anamnesis.xml',
      );
    });

    test('four segments (skill) — same rule, no special case', () {
      expect(
        r.fqdnToRelPath('swift.coding.craft.skill'),
        'skill/craft/coding/swift/swift.xml',
      );
    });

    test('agent — the whole organism, file named for the particle', () {
      expect(r.fqdnToRelPath('alfred.agent'), 'agent/alfred/alfred.xml');
    });

    test('arbitrary depth', () {
      expect(r.fqdnToRelPath('foo.bar.baz'), 'baz/bar/foo/foo.xml');
    });

    test('not an FQDN (single segment) → null', () {
      expect(r.fqdnToRelPath('nodot'), isNull);
    });

    test('empty → null', () {
      expect(r.fqdnToRelPath(''), isNull);
    });
  });

  group('relPathToFqdn — symmetric inverse of fqdnToRelPath', () {
    final r = PathResolver(MemoryFileSystem(), const []);

    test('round-trips a two-segment FQDN', () {
      expect(r.relPathToFqdn('soul/alfred/alfred.xml'), 'alfred.soul');
    });

    test('round-trips a four-segment FQDN', () {
      expect(
        r.relPathToFqdn('skill/craft/coding/swift/swift.xml'),
        'swift.coding.craft.skill',
      );
    });

    test('arbitrary depth', () {
      expect(r.relPathToFqdn('baz/bar/foo/foo.xml'), 'foo.bar.baz');
    });

    test('an xi:include member (basename ≠ dir) is not a particle root → null', () {
      expect(
        r.relPathToFqdn('skill/craft/coding/dart/skill_abstract.xml'),
        isNull,
      );
    });

    test('bijection: fqdnToRelPath ∘ relPathToFqdn is identity', () {
      for (final fqdn in const [
        'alfred.soul',
        'anamnesis.faculty',
        'swift.coding.craft.skill',
        'foo.bar.baz',
      ]) {
        expect(r.relPathToFqdn(r.fqdnToRelPath(fqdn)!), fqdn);
      }
    });
  });

  group('resolve — relative-file first, then FQDN', () {
    late MemoryFileSystem fs;
    late PathResolver r;

    setUp(() {
      fs = MemoryFileSystem();
      _seed(fs, '/tree/faculty/anamnesis/anamnesis.xml', 'ANAMNESIS_ATOM');
      _seed(fs, '/tree/skill/craft/coding/dart/dart.xml', 'DART_ATOM');
      _seed(fs, '/tree/skill/craft/coding/dart/skill_abstract.xml', 'DART_ABSTRACT');
      r = PathResolver(fs, const ['/tree']);
    });

    test('relative member resolves against baseDir (THE bug fix)', () {
      // BEHAVIOR: a bare member href, resolved beside the including atom.xml.
      final got = r.resolve('skill_abstract.xml', '/tree/skill/craft/coding/dart');
      // VERIFY
      expect(got, isNotNull, reason: 'relative include must resolve, not 404');
      expect(got!.content, 'DART_ABSTRACT');
      expect(got.canonicalPath, endsWith('skill_abstract.xml'));
    });

    test('FQDN resolves against the tree root, baseDir irrelevant', () {
      final got = r.resolve('anamnesis.faculty', '/some/unrelated/dir');
      expect(got, isNotNull);
      expect(got!.content, 'ANAMNESIS_ATOM');
    });

    test('relative wins over FQDN when both could resolve', () {
      // SETUP: a literal file named like an FQDN, sitting beside the includer.
      _seed(fs, '/tree/skill/craft/coding/dart/anamnesis.faculty', 'LOCAL_SHADOW');
      // BEHAVIOR
      final got = r.resolve('anamnesis.faculty', '/tree/skill/craft/coding/dart');
      // VERIFY: the local file shadows the FQDN — relative is tried first.
      expect(got!.content, 'LOCAL_SHADOW', reason: 'relative-first precedence');
    });

    test('missing relative AND missing FQDN → null', () {
      expect(r.resolve('ghost.faculty', '/tree'), isNull);
      expect(r.resolve('missing.xml', '/tree'), isNull);
    });
  });

  group('resolve — which(1)-style across multiple roots', () {
    test('first root that has the FQDN wins', () {
      // SETUP: two roots, both carry the same FQDN with different markers.
      final fs = MemoryFileSystem();
      _seed(fs, '/a/faculty/anamnesis/anamnesis.xml', 'FROM_A');
      _seed(fs, '/b/faculty/anamnesis/anamnesis.xml', 'FROM_B');
      final r = PathResolver(fs, const ['/a', '/b']);
      // BEHAVIOR + VERIFY
      expect(r.resolve('anamnesis.faculty', '/x')!.content, 'FROM_A');
    });

    test('falls through to a later root when the first lacks it', () {
      final fs = MemoryFileSystem();
      _seed(fs, '/b/faculty/anamnesis/anamnesis.xml', 'FROM_B');
      final r = PathResolver(fs, const ['/a', '/b']);
      expect(r.resolve('anamnesis.faculty', '/x')!.content, 'FROM_B');
    });
  });
}
