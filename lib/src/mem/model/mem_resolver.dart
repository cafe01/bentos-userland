import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'mem_node.dart';

/// Resolves the memory index for an agent at a place.
///
/// FileSystem-injected for hermetic tests.
final class MemResolver {
  const MemResolver({required this.agent, required this.fileSystem});

  final String agent;
  final FileSystem fileSystem;

  MemNode? resolve(String placeDir) => MemNode.load(nodePathAt(placeDir), fileSystem);

  String nodePathAt(String placeDir) => p.join(placeDir, '.mem', agent, 'mem.yml');

  String agentDirAt(String placeDir) => p.join(placeDir, '.mem', agent);

  List<String> contentFilesAt(String placeDir) {
    final dir = fileSystem.directory(agentDirAt(placeDir));
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .map((f) => f.path)
        .toList()
      ..sort();
  }
}
