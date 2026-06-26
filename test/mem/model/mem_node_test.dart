import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late MemoryFileSystem fs;
  const place = '/test-place';
  const agent = 'tester';

  String agentDir() => p.join(place, '.mem', agent);

  String writeNode(String yaml) {
    fs.directory(agentDir()).createSync(recursive: true);
    final path = p.join(agentDir(), 'mem.yml');
    fs.file(path).writeAsStringSync(yaml);
    return path;
  }

  setUp(() => fs = MemoryFileSystem());

  group('MemNode', () {
    test('loads a minimal graph node', () {
      final path = writeNode('''
agent: tester
scope: root
session: 304
updated: 2026-03-23

edges:
  episodic: []
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs);
      expect(node, isNotNull);
      expect(node!.agent, 'tester');
      expect(node.scope, 'root');
      expect(node.session, 304);
      expect(node.updated, '2026-03-23');
      expect(node.allPages, isEmpty);
    });

    test('parses episodic pages with weights', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  episodic:
    - session-landscape.md: 1.0
    - team-state.md: 0.8
  semantic:
    - product-decisions.md: 1.0
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      expect(node.pagesOf(MemPageType.episodic), hasLength(2));
      expect(node.pagesOf(MemPageType.semantic), hasLength(1));

      final epi = node.pagesOf(MemPageType.episodic);
      expect(epi[0].target, 'session-landscape.md');
      expect(epi[0].weight, 1.0);
      expect(epi[0].type, MemPageType.episodic);
      expect(epi[1].target, 'team-state.md');
      expect(epi[1].weight, 0.8);
    });

    test('parses procedural pages', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  procedural:
    - craft-patterns.md: 1.0
    - idioms.md: 0.9
  episodic: []
  semantic: []
  prospective: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      final proc = node.pagesOf(MemPageType.procedural);
      expect(proc, hasLength(2));
      expect(proc[0].target, 'craft-patterns.md');
      expect(proc[0].weight, 1.0);
      expect(proc[1].target, 'idioms.md');
      expect(proc[1].weight, 0.9);
    });

    test('parses autobiographical pages', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  autobiographical:
    - arc-s400.md: 0.9
  episodic: []
  semantic: []
  prospective: []
  procedural: []
''');
      final node = MemNode.load(path, fs)!;
      expect(node.pagesOf(MemPageType.autobiographical), hasLength(1));
      expect(node.pagesOf(MemPageType.autobiographical).first.target, 'arc-s400.md');
    });

    test('plain string targets default to weight 1.0', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  episodic:
    - fallback.md
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      final page = node.pagesOf(MemPageType.episodic).single;
      expect(page.target, 'fallback.md');
      expect(page.weight, 1.0);
    });

    test('pagesAbove filters by minimum weight', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  semantic:
    - a.md: 0.9
    - b.md: 0.5
    - c.md: 0.2
  episodic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      expect(node.pagesAbove(MemPageType.semantic, 0.5), hasLength(2));
      expect(node.pagesAbove(MemPageType.semantic, 0.9), hasLength(1));
      expect(node.pagesAbove(MemPageType.semantic, 0.0), hasLength(3));
    });

    test('resolveTarget returns absolute path under agent dir', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  episodic:
    - landscape.md: 1.0
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      final page = node.pagesOf(MemPageType.episodic).single;
      final resolved = node.resolveTarget(page);
      expect(resolved, p.join(place, '.mem', agent, 'landscape.md'));
    });

    test('returns null for nonexistent file', () {
      expect(MemNode.load('/nonexistent/path.yml', fs), isNull);
    });

    test('returns null for invalid YAML', () {
      final path = writeNode('not: [valid: yaml: {{');
      expect(MemNode.load(path, fs), isNull);
    });

    test('integer weight parsed as double', () {
      final path = writeNode('''
agent: tester
scope: root

edges:
  episodic:
    - a.md: 1
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      expect(node.pagesOf(MemPageType.episodic).single.weight, 1.0);
    });

    test('scope inferred from directory when absent', () {
      // mem.yml at /test-place/.mem/tester/mem.yml → scope from place dirname
      final path = writeNode('''
agent: tester

edges:
  episodic: []
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
      final node = MemNode.load(path, fs)!;
      expect(node.scope, isNotEmpty);
    });
  });

  group('MemPage', () {
    test('weightLabel formats with one decimal', () {
      const page = MemPage(type: MemPageType.episodic, target: 'test.md', weight: 0.75);
      expect(page.weightLabel, 'w:0.8');
    });

    test('name strips .md suffix', () {
      const page = MemPage(type: MemPageType.semantic, target: 'my-note.md', weight: 0.9);
      expect(page.name, 'my-note');
    });

    test('name returns target unchanged without .md', () {
      const page = MemPage(type: MemPageType.semantic, target: 'my-note', weight: 0.9);
      expect(page.name, 'my-note');
    });

    test('parse: canonical "- name.md: weight" shape', () {
      final yaml = loadYaml('- foo.md: 0.8') as YamlList;
      final page = MemPage.parse(MemPageType.episodic, yaml.first);
      expect(page.target, 'foo.md');
      expect(page.weight, 0.8);
    });

    test('parse: legacy flow-map key without crashing', () {
      final yaml = loadYaml('- {name: foo, weight: 0.9}: 1.0') as YamlList;
      final page = MemPage.parse(MemPageType.semantic, yaml.first);
      expect(page.target, 'foo');
      expect(page.weight, 0.9);
    });
  });
}
