import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/model/mem_frontmatter.dart';
import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:bentos_userland/src/mem/model/mem_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FrontmatterFields.parse', () {
    test('returns empty fields and full content when no frontmatter', () {
      const body = 'plain body\nno frontmatter here';
      final (fields, parsed) = FrontmatterFields.parse(body);
      expect(fields.isEmpty, isTrue);
      expect(parsed, body);
    });

    test('parses telos only', () {
      const content = '---\ntelos: To capture the seam model\n---\n\nbody text';
      final (fields, body) = FrontmatterFields.parse(content);
      expect(fields.telos, 'To capture the seam model');
      expect(fields.gist, isNull);
      expect(body, 'body text');
    });

    test('parses all four fields', () {
      const content = '''---
telos: To explain X
gist: X is a mechanism that does Y
links:
  - hq/docs/x.md
  - hq/tickets/t-1.md
tags:
  - architecture
  - kernel
---

The full body.
''';
      final (fields, body) = FrontmatterFields.parse(content);
      expect(fields.telos, 'To explain X');
      expect(fields.gist, 'X is a mechanism that does Y');
      expect(fields.links, ['hq/docs/x.md', 'hq/tickets/t-1.md']);
      expect(fields.tags, ['architecture', 'kernel']);
      expect(body, 'The full body.\n');
    });

    test('returns full content when closing delimiter missing', () {
      const content = '---\ntelos: To …\nno closing delimiter';
      final (fields, body) = FrontmatterFields.parse(content);
      expect(fields.isEmpty, isTrue);
      expect(body, content);
    });

    test('parses quoted gist with colons', () {
      const content = '---\ngist: "A: B maps to C: D"\n---\n\nbody';
      final (fields, body) = FrontmatterFields.parse(content);
      expect(fields.gist, 'A: B maps to C: D');
      expect(body, 'body');
    });
  });

  group('FrontmatterFields.serialize', () {
    test('returns empty string when fields are empty', () {
      expect(const FrontmatterFields().serialize(), '');
    });

    test('serializes telos only', () {
      final f = FrontmatterFields(telos: 'To capture X');
      expect(f.serialize(), '---\ntelos: To capture X\n---');
    });

    test('serializes gist with colon-space as quoted', () {
      final f = FrontmatterFields(gist: 'A: B and C: D');
      expect(f.serialize(), contains('gist: "A: B and C: D"'));
    });

    test('serializes links as block list', () {
      final f = FrontmatterFields(links: ['hq/docs/x.md', 'hq/tickets/t-1.md']);
      expect(
        f.serialize(),
        contains('links:\n  - hq/docs/x.md\n  - hq/tickets/t-1.md'),
      );
    });

    test('serializes tags as block list', () {
      final f = FrontmatterFields(tags: ['architecture', 'kernel']);
      expect(f.serialize(), contains('tags:\n  - architecture\n  - kernel'));
    });

    test('canonical field order: telos gist links tags', () {
      final f = FrontmatterFields(
        telos: 'To X',
        gist: 'X is Y',
        links: ['a.md'],
        tags: ['t1'],
      );
      final lines = f.serialize().split('\n');
      final telosIdx = lines.indexWhere((l) => l.startsWith('telos:'));
      final gistIdx = lines.indexWhere((l) => l.startsWith('gist:'));
      final linksIdx = lines.indexWhere((l) => l.startsWith('links:'));
      final tagsIdx = lines.indexWhere((l) => l.startsWith('tags:'));
      expect(telosIdx, lessThan(gistIdx));
      expect(gistIdx, lessThan(linksIdx));
      expect(linksIdx, lessThan(tagsIdx));
    });
  });

  group('FrontmatterFields.merge', () {
    test('overlay wins for non-null fields', () {
      final base = FrontmatterFields(telos: 'old telos', gist: 'old gist');
      final overlay = FrontmatterFields(gist: 'new gist');
      final merged = base.merge(overlay);
      expect(merged.telos, 'old telos');
      expect(merged.gist, 'new gist');
    });

    test('null overlay fields leave base intact', () {
      final base = FrontmatterFields(
        telos: 'T',
        gist: 'G',
        links: ['a.md'],
        tags: ['t1'],
      );
      final merged = base.merge(const FrontmatterFields());
      expect(merged.telos, 'T');
      expect(merged.gist, 'G');
      expect(merged.links, ['a.md']);
      expect(merged.tags, ['t1']);
    });

    test('tags overlay replaces entire list', () {
      final base = FrontmatterFields(tags: ['old']);
      final overlay = FrontmatterFields(tags: ['new1', 'new2']);
      expect(base.merge(overlay).tags, ['new1', 'new2']);
    });
  });

  group('FrontmatterFields.applyTo', () {
    test('returns body unchanged when fields are empty', () {
      expect(const FrontmatterFields().applyTo('just body'), 'just body');
    });

    test('prepends frontmatter with blank line separator', () {
      final f = FrontmatterFields(telos: 'To X');
      expect(f.applyTo('body text'), '---\ntelos: To X\n---\n\nbody text');
    });

    test('no body → frontmatter with trailing newline only', () {
      final f = FrontmatterFields(telos: 'To X');
      expect(f.applyTo(''), '---\ntelos: To X\n---\n');
    });

    test('round-trip: serialize then parse recovers all fields', () {
      final orig = FrontmatterFields(
        telos: 'To explain X',
        gist: 'X is a mechanism: it maps inputs to outputs',
        links: ['hq/docs/x.md', 'hq/tickets/t-1.md'],
        tags: ['architecture', 'kernel'],
      );
      final content = orig.applyTo('Full body here.\n');
      final (parsed, body) = FrontmatterFields.parse(content);
      expect(parsed.telos, orig.telos);
      expect(parsed.gist, orig.gist);
      expect(parsed.links, orig.links);
      expect(parsed.tags, orig.tags);
      expect(body, 'Full body here.\n');
    });
  });

  group('write-path round-trips via MemWriter', () {
    late MemoryFileSystem fs;
    const place = '/test-place';
    const agent = 'tester';
    late String agentDir;

    setUp(() {
      fs = MemoryFileSystem();
      agentDir = p.join(place, '.mem', agent);
      fs.directory(agentDir).createSync(recursive: true);
      fs.file(p.join(agentDir, 'mem.yml')).writeAsStringSync('''
agent: $agent
scope: root
updated: 2026-01-01

edges:
  episodic: []
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
    });

    MemNode load() => MemResolver(agent: agent, fileSystem: fs).resolve(place)!;
    String readPage(String name) =>
        fs.file(p.join(agentDir, '$name.md')).readAsStringSync();

    test('create with telos+gist round-trips', () {
      final fields = FrontmatterFields(telos: 'To test', gist: 'The gist of it');
      MemWriter(fs).create(
        load(), MemPageType.semantic, 'page1', fields.applyTo('Full body.\n'), 0.8);

      final (parsed, body) = FrontmatterFields.parse(readPage('page1'));
      expect(parsed.telos, 'To test');
      expect(parsed.gist, 'The gist of it');
      expect(body, 'Full body.\n');
    });

    test('create with links and tags round-trips', () {
      final fields = FrontmatterFields(
        telos: 'To test links and tags',
        links: ['hq/docs/spec.md'],
        tags: ['architecture'],
      );
      MemWriter(fs).create(
        load(), MemPageType.semantic, 'page2', fields.applyTo('body'), 0.7);

      final (parsed, _) = FrontmatterFields.parse(readPage('page2'));
      expect(parsed.links, ['hq/docs/spec.md']);
      expect(parsed.tags, ['architecture']);
    });

    test('second remember without --gist preserves existing gist', () {
      final writer = MemWriter(fs);
      writer.create(
        load(), MemPageType.semantic, 'page3',
        FrontmatterFields(telos: 'To X', gist: 'The gist').applyTo('body'), 0.8);

      final node = load();
      final page = node.pagesOf(MemPageType.semantic).first;
      final (existingFields, existingBody) = FrontmatterFields.parse(readPage('page3'));
      final merged = existingFields.merge(FrontmatterFields(telos: 'To X revised'));
      writer.update(node, MemPageType.semantic, page,
          content: merged.applyTo(existingBody));

      final (parsed, _) = FrontmatterFields.parse(readPage('page3'));
      expect(parsed.telos, 'To X revised');
      expect(parsed.gist, 'The gist');
    });

    test('links list is replaced entirely on update', () {
      final writer = MemWriter(fs);
      writer.create(
        load(), MemPageType.semantic, 'page4',
        FrontmatterFields(links: ['hq/old.md']).applyTo('body'), 0.8);

      final node = load();
      final page = node.pagesOf(MemPageType.semantic).first;
      final (existingFields, existingBody) = FrontmatterFields.parse(readPage('page4'));
      final merged = existingFields.merge(FrontmatterFields(links: ['hq/new.md']));
      writer.update(node, MemPageType.semantic, page,
          content: merged.applyTo(existingBody));

      final (parsed, _) = FrontmatterFields.parse(readPage('page4'));
      expect(parsed.links, ['hq/new.md']);
    });

    test('body is not affected by frontmatter-only update', () {
      const originalBody = 'Original body content.\n';
      final writer = MemWriter(fs);
      writer.create(
        load(), MemPageType.semantic, 'page5',
        FrontmatterFields(telos: 'To X').applyTo(originalBody), 0.8);

      final node = load();
      final page = node.pagesOf(MemPageType.semantic).first;
      final (existingFields, existingBody) = FrontmatterFields.parse(readPage('page5'));
      final merged = existingFields.merge(FrontmatterFields(gist: 'Added gist'));
      writer.update(node, MemPageType.semantic, page,
          content: merged.applyTo(existingBody));

      final (parsed, body) = FrontmatterFields.parse(readPage('page5'));
      expect(parsed.gist, 'Added gist');
      expect(body, originalBody);
    });
  });
}
