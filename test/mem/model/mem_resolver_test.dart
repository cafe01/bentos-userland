import 'package:file/memory.dart';
import 'package:bentos_userland/src/mem/model/mem_resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  const place = '/test-place';
  const agent = 'tester';

  setUp(() => fs = MemoryFileSystem());

  void seedNode() {
    final agentDir = p.join(place, '.mem', agent);
    fs.directory(agentDir).createSync(recursive: true);
    fs.file(p.join(agentDir, 'mem.yml')).writeAsStringSync('''
agent: $agent
scope: test
session: 1

edges:
  episodic: []
  semantic: []
  prospective: []
  procedural: []
  autobiographical: []
''');
  }

  group('MemResolver', () {
    test('resolve finds agent node at place', () {
      seedNode();
      final resolver = MemResolver(agent: agent, fileSystem: fs);
      final node = resolver.resolve(place);
      expect(node, isNotNull);
      expect(node!.agent, agent);
    });

    test('resolve returns null when no node exists', () {
      final resolver = MemResolver(agent: agent, fileSystem: fs);
      expect(resolver.resolve(place), isNull);
    });

    test('contentFilesAt lists md files in agent directory', () {
      seedNode();
      final agentDir = p.join(place, '.mem', agent);
      fs.file(p.join(agentDir, 'landscape.md')).writeAsStringSync('content a');
      fs.file(p.join(agentDir, 'decisions.md')).writeAsStringSync('content b');
      fs.file(p.join(agentDir, 'not-md.txt')).writeAsStringSync('ignored');

      final resolver = MemResolver(agent: agent, fileSystem: fs);
      final files = resolver.contentFilesAt(place);
      expect(files, hasLength(2));
      expect(files.every((f) => f.endsWith('.md')), isTrue);
    });

    test('contentFilesAt returns empty when no agent dir', () {
      final resolver = MemResolver(agent: agent, fileSystem: fs);
      expect(resolver.contentFilesAt(place), isEmpty);
    });

    test('nodePathAt returns correct path', () {
      final resolver = MemResolver(agent: agent, fileSystem: fs);
      expect(
        resolver.nodePathAt(place),
        p.join(place, '.mem', agent, 'mem.yml'),
      );
    });

    test('agentDirAt returns correct path', () {
      final resolver = MemResolver(agent: 'gideon', fileSystem: fs);
      expect(
        resolver.agentDirAt(place),
        p.join(place, '.mem', 'gideon'),
      );
    });
  });
}
