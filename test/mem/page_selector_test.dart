import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:bentos_userland/src/mem/page_selector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  const place = '/test-place';
  const agent = 'tester';

  setUp(() => fs = MemoryFileSystem());

  MemNode buildNode({
    Map<MemPageType, Map<String, double>> pages = const {},
    Map<String, String> content = const {},
  }) {
    final agentDir = p.join(place, '.mem', agent);
    fs.directory(agentDir).createSync(recursive: true);
    final buf = StringBuffer()
      ..writeln('agent: $agent')
      ..writeln('scope: test')
      ..writeln('edges:');
    for (final type in MemPageType.values) {
      final typePages = pages[type] ?? {};
      buf.write('  ${type.name}:');
      if (typePages.isEmpty) {
        buf.writeln(' []');
      } else {
        buf.writeln();
        for (final e in typePages.entries) {
          buf.writeln('    - ${e.key}.md: ${e.value}');
        }
      }
    }
    fs.file(p.join(agentDir, 'mem.yml')).writeAsStringSync(buf.toString());
    for (final e in content.entries) {
      fs.file(p.join(agentDir, '${e.key}.md')).writeAsStringSync(e.value);
    }
    return MemResolver(agent: agent, fileSystem: fs).resolve(place)!;
  }

  const selector = PageSelector();

  group('PageSelector', () {
    test('minWeight includes the boundary (>=)', () {
      final node = buildNode(pages: {
        MemPageType.episodic: {'ep-low': 0.4, 'ep-boundary': 0.5, 'ep-high': 0.8},
      });
      final result = selector.select(node, minWeight: 0.5);
      expect(result.any((pg) => pg.name == 'ep-boundary'), isTrue,
          reason: 'boundary weight 0.5 must be included');
      expect(result.every((pg) => pg.weight >= 0.5), isTrue);
      expect(result.any((pg) => pg.name == 'ep-low'), isFalse);
    });

    test('maxWeight includes the boundary (<=)', () {
      final node = buildNode(pages: {
        MemPageType.episodic: {'ep-low': 0.4, 'ep-boundary': 0.7, 'ep-high': 0.9},
      });
      final result = selector.select(node, maxWeight: 0.7);
      expect(result.any((pg) => pg.name == 'ep-boundary'), isTrue,
          reason: 'boundary weight 0.7 must be included');
      expect(result.every((pg) => pg.weight <= 0.7), isTrue);
      expect(result.any((pg) => pg.name == 'ep-high'), isFalse);
    });

    test('band (min AND max) intersects correctly', () {
      final node = buildNode(pages: {
        MemPageType.semantic: {'too-low': 0.3, 'in-band': 0.6, 'too-high': 0.9},
      });
      final result = selector.select(node, minWeight: 0.5, maxWeight: 0.8);
      expect(result, hasLength(1));
      expect(result.single.name, 'in-band');
    });

    test('type narrows to one mode', () {
      final node = buildNode(pages: {
        MemPageType.episodic: {'ep-a': 0.8},
        MemPageType.semantic: {'sem-a': 0.7, 'sem-b': 0.6},
        MemPageType.procedural: {'proc-a': 0.9},
      });
      final result = selector.select(node, type: MemPageType.semantic);
      expect(result.every((pg) => pg.type == MemPageType.semantic), isTrue);
      expect(result, hasLength(2));
    });

    test('tag narrows to pages carrying that tag', () {
      final node = buildNode(
        pages: {
          MemPageType.episodic: {'tagged': 0.8, 'untagged': 0.6},
        },
        content: {
          'tagged': '---\ntags:\n  - mytag\n---\nbody',
          'untagged': 'no frontmatter, no tag',
        },
      );
      final result = selector.select(node, tag: 'mytag');
      expect(result, hasLength(1));
      expect(result.single.name, 'tagged');
    });

    test('predicates compose (AND): type + minWeight', () {
      final node = buildNode(pages: {
        MemPageType.episodic: {'ep-high': 0.9, 'ep-low': 0.4},
        MemPageType.semantic: {'sem-high': 0.9},
      });
      final result =
          selector.select(node, type: MemPageType.episodic, minWeight: 0.8);
      expect(result, hasLength(1));
      expect(result.single.name, 'ep-high');
    });

    test('empty result is empty, not error', () {
      final node = buildNode(pages: {
        MemPageType.episodic: {'ep-a': 0.5},
      });
      final result = selector.select(node, minWeight: 1.1);
      expect(result, isEmpty);
    });

    test('output stays in composition order regardless of predicate', () {
      final node = buildNode(pages: {
        MemPageType.prospective: {'intent-a': 0.8},
        MemPageType.semantic: {'sem-a': 0.8},
        MemPageType.autobiographical: {'arc-a': 0.8},
        MemPageType.episodic: {'ep-a': 0.8},
        MemPageType.procedural: {'craft-a': 0.8},
      });
      final result = selector.select(node);
      final types = result.map((pg) => pg.type).toList();

      int first(MemPageType t) => types.indexOf(t);
      expect(first(MemPageType.autobiographical), lessThan(first(MemPageType.episodic)));
      expect(first(MemPageType.episodic), lessThan(first(MemPageType.semantic)));
      expect(first(MemPageType.semantic), lessThan(first(MemPageType.procedural)));
      expect(first(MemPageType.procedural), lessThan(first(MemPageType.prospective)));
    });
  });
}
