import 'package:file/file.dart';
import 'package:yaml/yaml.dart';

import '../residence.dart';

/// Lazily-parsed metadata for a place, read from `.place/place.yaml`.
///
/// All fields optional; an absent file yields empty defaults, a malformed one
/// degrades to defaults plus a surfaced [warning] — never a crash.
final class PlaceMeta {
  const PlaceMeta({this.name, this.description, this.owner, this.warning});

  final String? name;
  final String? description;
  final String? owner;

  /// Surfaced when `place.yaml` is present but unparseable; null otherwise.
  final String? warning;

  /// Load metadata for the place rooted at [placeRoot].
  static PlaceMeta load(Directory placeRoot, FileSystem fs) {
    final file = Residence.metaFile(placeRoot, fs);
    if (!file.existsSync()) return const PlaceMeta();
    try {
      final dynamic doc = loadYaml(file.readAsStringSync());
      if (doc is! YamlMap) return const PlaceMeta();
      return PlaceMeta(
        name: _str(doc['name']),
        description: _str(doc['description']),
        owner: _str(doc['owner']),
      );
    } on YamlException catch (e) {
      return PlaceMeta(warning: '${file.path}: ${e.message}');
    }
  }

  static String? _str(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}
