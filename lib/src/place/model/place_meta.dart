import 'dart:io';

import 'package:file/file.dart' as f;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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

  /// Load metadata for the place rooted at [placeRoot]. Reads through [fs]
  /// when given — the old model's injected `package:file` filesystem, whose
  /// entities implement the `dart:io` interfaces this method type-checks
  /// against. Bare `dart:io` otherwise (the new model, hermetic via
  /// `IOOverrides`/zone).
  static PlaceMeta load(Directory placeRoot, {f.FileSystem? fs}) {
    final path = p.join(placeRoot.path, '.place', 'place.yaml');
    final File file = fs == null ? File(path) : fs.file(path) as File;
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
