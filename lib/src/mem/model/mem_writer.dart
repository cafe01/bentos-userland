import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'mem_node.dart';

/// Writes to the memory index — content files and mem.yml — atomically.
///
/// FileSystem-injected for hermetic tests.
final class MemWriter {
  const MemWriter(this.fileSystem);

  final FileSystem fileSystem;

  void create(
    MemNode node,
    MemPageType type,
    String pageName,
    String? content,
    double weight,
  ) {
    final target = '$pageName.md';
    final file = fileSystem.file(p.join(node.agentDir, target));
    if (content != null) {
      file.writeAsStringSync(content);
    } else if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    final updated = _copy(node);
    updated.putIfAbsent(type, () => [])
        .add(MemPage(type: type, target: target, weight: weight));
    _flush(node, updated);
  }

  void update(
    MemNode node,
    MemPageType existingType,
    MemPage existing, {
    String? content,
    double? weight,
    MemPageType? type,
  }) {
    if (content != null) {
      fileSystem.file(p.join(node.agentDir, existing.target)).writeAsStringSync(content);
    }
    final newWeight = weight ?? existing.weight;
    final newType = type ?? existingType;
    if (newType != existingType || newWeight != existing.weight) {
      final updated = _copy(node);
      updated[existingType]!.removeWhere((e) => e.target == existing.target);
      updated.putIfAbsent(newType, () => [])
          .add(MemPage(type: newType, target: existing.target, weight: newWeight));
      _flush(node, updated);
    }
  }

  void delete(MemNode node, MemPageType type, MemPage page) {
    final file = fileSystem.file(p.join(node.agentDir, page.target));
    if (file.existsSync()) file.deleteSync();
    final updated = _copy(node);
    updated[type]!.removeWhere((e) => e.target == page.target);
    _flush(node, updated);
  }

  Map<MemPageType, List<MemPage>> _copy(MemNode node) => {
        for (final t in MemPageType.values) t: List<MemPage>.from(node.pagesOf(t)),
      };

  void _flush(MemNode node, Map<MemPageType, List<MemPage>> pageMap) {
    final now = DateTime.now();
    final date = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final buf = StringBuffer()
      ..writeln('agent: ${node.agent}')
      ..writeln('scope: ${node.scope}');
    if (node.session != null) buf.writeln('session: ${node.session}');
    buf
      ..writeln('updated: $date')
      ..writeln()
      ..writeln('edges:');

    for (final type in MemPageType.values) {
      final typePages = pageMap[type] ?? [];
      buf.write('  ${type.name}:');
      if (typePages.isEmpty) {
        buf.writeln(' []');
      } else {
        buf.writeln();
        for (final page in typePages) {
          buf.writeln('    - ${page.target}: ${page.weight.toStringAsFixed(1)}');
        }
      }
    }

    fileSystem.file(node.path).writeAsStringSync(buf.toString());
  }
}
