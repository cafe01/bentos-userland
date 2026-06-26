import 'package:file/file.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The memory modes — surface vocabulary is "page", type is its mode.
enum MemPageType {
  episodic,
  semantic,
  prospective,
  procedural,
  autobiographical;

  bool get isContent => true;
}

/// Composition order for display: autobiographical → episodic → semantic → procedural → prospective.
const List<MemPageType> kCompositionOrder = [
  MemPageType.autobiographical,
  MemPageType.episodic,
  MemPageType.semantic,
  MemPageType.procedural,
  MemPageType.prospective,
];

/// A single page entry in the memory index (formerly MemEdge).
final class MemPage {
  const MemPage({
    required this.type,
    required this.target,
    required this.weight,
  });

  factory MemPage.parse(MemPageType type, dynamic yaml) {
    if (yaml is String) {
      return MemPage(type: type, target: yaml, weight: 1.0);
    }
    if (yaml is YamlMap && yaml.length == 1) {
      final entry = yaml.entries.first;
      final key = entry.key;
      if (key is String) {
        return MemPage(
          type: type,
          target: key,
          weight: _parseWeight(entry.value) ?? 1.0,
        );
      }
      if (key is YamlMap && key['name'] is String) {
        return MemPage(
          type: type,
          target: key['name'] as String,
          weight: _parseWeight(key['weight']) ?? _parseWeight(entry.value) ?? 1.0,
        );
      }
    }
    return MemPage(type: type, target: yaml.toString(), weight: 1.0);
  }

  static double? _parseWeight(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  final MemPageType type;

  /// Target filename (relative to agent directory `.mem/<agent>/`).
  final String target;

  final double weight;

  String get weightLabel => 'w:${weight.toStringAsFixed(1)}';

  /// The page name (stem of [target], without `.md`).
  String get name => target.endsWith('.md') ? target.substring(0, target.length - 3) : target;
}

/// The memory index for one agent at one place.
///
/// Parsed from `.mem/<agent>/mem.yml`. Holds typed, weighted pages.
/// FileSystem-injected for hermetic tests.
final class MemNode {
  const MemNode({
    required this.path,
    required this.agent,
    required this.scope,
    this.session,
    this.updated,
    this.pages = const {},
  });

  static MemNode? load(String filePath, FileSystem fs) {
    final file = fs.file(filePath);
    if (!file.existsSync()) return null;
    try {
      final doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) return null;
      return MemNode._fromYaml(filePath, doc);
    } on YamlException {
      return null;
    }
  }

  factory MemNode._fromYaml(String filePath, YamlMap doc) {
    final pages = <MemPageType, List<MemPage>>{};
    final edgesYaml = doc['edges'];
    if (edgesYaml is YamlMap) {
      for (final type in MemPageType.values) {
        final targets = edgesYaml[type.name];
        if (targets is YamlList) {
          pages[type] = [for (final t in targets) MemPage.parse(type, t)];
        }
      }
    }
    return MemNode(
      path: filePath,
      agent: doc['agent'] as String? ?? 'unknown',
      scope: doc['scope'] as String? ?? p.basename(p.dirname(p.dirname(p.dirname(filePath)))),
      session: _parseInt(doc['session']),
      updated: doc['updated']?.toString(),
      pages: pages,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  final String path;
  final String agent;
  final String scope;
  final int? session;
  final String? updated;
  final Map<MemPageType, List<MemPage>> pages;

  String get agentDir => p.dirname(path);
  String get placeDir => p.dirname(p.dirname(agentDir));

  Iterable<MemPage> get allPages => pages.values.expand((e) => e);

  List<MemPage> pagesOf(MemPageType type) => pages[type] ?? const [];

  List<MemPage> pagesAbove(MemPageType type, double minWeight) =>
      pagesOf(type).where((e) => e.weight >= minWeight).toList();

  String resolveTarget(MemPage page) => p.normalize(p.join(agentDir, page.target));
}
