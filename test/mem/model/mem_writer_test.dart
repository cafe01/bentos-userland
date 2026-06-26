import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/model/mem_node.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:bentos_userland/src/mem/model/mem_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  const place = '/test-place';
  const agent = 'tester';
  late String agentDir;

  setUp(() {
    fs = MemoryFileSystem();
    agentDir = p.join(place, '.mem', agent);
    fs.directory(agentDir).createSync(recursive: true);
  });

  MemNode load() => MemResolver(agent: agent, fileSystem: fs).resolve(place)!;
  MemWriter writer() => MemWriter(fs);

  void seedNode() {
    fs.file(p.join(agentDir, 'mem.yml')).writeAsStringSync('''
agent: $agent
scope: root
session: 10
updated: 2026-01-01

edges:
  episodic:
    - landscape.md: 1.0
  semantic:
    - decisions.md: 0.9
  prospective: []
  procedural: []
  autobiographical: []
''');
    fs.file(p.join(agentDir, 'landscape.md')).writeAsStringSync('landscape');
    fs.file(p.join(agentDir, 'decisions.md')).writeAsStringSync('decisions');
  }

  group('MemWriter.create', () {
    test('writes content file and adds page to mem.yml', () {
      seedNode();
      writer().create(load(), MemPageType.semantic, 'new-topic', 'hello', 0.7);

      final updated = load();
      expect(
        updated.pagesOf(MemPageType.semantic)
            .any((pg) => pg.target == 'new-topic.md' && pg.weight == 0.7),
        isTrue,
      );
      expect(fs.file(p.join(agentDir, 'new-topic.md')).readAsStringSync(), 'hello');
    });

    test('preserves existing pages', () {
      seedNode();
      writer().create(load(), MemPageType.episodic, 'extra', 'extra', 0.5);

      final updated = load();
      expect(
        updated.pagesOf(MemPageType.episodic).map((pg) => pg.target),
        containsAll(['landscape.md', 'extra.md']),
      );
    });

    test('null content does not overwrite existing content file', () {
      seedNode();
      fs.file(p.join(agentDir, 'intentions.md')).writeAsStringSync('keep me');
      writer().create(load(), MemPageType.prospective, 'intentions', null, 1.0);

      expect(fs.file(p.join(agentDir, 'intentions.md')).readAsStringSync(), 'keep me');
      expect(
        load().pagesOf(MemPageType.prospective)
            .any((pg) => pg.target == 'intentions.md' && pg.weight == 1.0),
        isTrue,
      );
    });
  });

  group('MemWriter.update', () {
    test('replaces content file when content provided', () {
      seedNode();
      final node = load();
      final page = node.pagesOf(MemPageType.episodic).first;
      writer().update(node, MemPageType.episodic, page, content: 'replaced');

      expect(fs.file(p.join(agentDir, 'landscape.md')).readAsStringSync(), 'replaced');
    });

    test('reweights page without touching content', () {
      seedNode();
      final node = load();
      final page = node.pagesOf(MemPageType.episodic).first;
      writer().update(node, MemPageType.episodic, page, weight: 0.3);

      final updated = load();
      final landscape =
          updated.pagesOf(MemPageType.episodic).firstWhere((pg) => pg.target == 'landscape.md');
      expect(landscape.weight, 0.3);
      expect(fs.file(p.join(agentDir, 'landscape.md')).readAsStringSync(), 'landscape');
    });

    test('moves page to new type', () {
      seedNode();
      final node = load();
      final page = node.pagesOf(MemPageType.episodic).first;
      writer().update(node, MemPageType.episodic, page, type: MemPageType.semantic);

      final updated = load();
      expect(
        updated.pagesOf(MemPageType.episodic).any((pg) => pg.target == 'landscape.md'),
        isFalse,
      );
      expect(
        updated.pagesOf(MemPageType.semantic).any((pg) => pg.target == 'landscape.md'),
        isTrue,
      );
    });
  });

  group('MemWriter.delete', () {
    test('removes page from mem.yml and deletes content file', () {
      seedNode();
      final node = load();
      final page = node.pagesOf(MemPageType.episodic).first;
      writer().delete(node, MemPageType.episodic, page);

      expect(
        load().pagesOf(MemPageType.episodic).any((pg) => pg.target == 'landscape.md'),
        isFalse,
      );
      expect(fs.file(p.join(agentDir, 'landscape.md')).existsSync(), isFalse);
    });

    test('other pages survive deletion', () {
      seedNode();
      final node = load();
      final page = node.pagesOf(MemPageType.episodic).first;
      writer().delete(node, MemPageType.episodic, page);

      expect(
        load().pagesOf(MemPageType.semantic).any((pg) => pg.target == 'decisions.md'),
        isTrue,
      );
    });
  });
}
