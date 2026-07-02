import 'package:file/file.dart';

import 'residence.dart';

/// Structural enumeration of the entity namespaces anchored at a place — the
/// union of directory names under `.place/mem/` and `.place/tx/`.
///
/// Entity-level only: blind to `scope`/`thread`, so a being with several scopes
/// appears once. Content-blind — never interprets what a namespace denotes. An
/// empty residence enumerates empty, never errors.
final class Inhabitants {
  Inhabitants._();

  /// The entity namespaces anchored directly at [placeRoot], sorted.
  static List<String> of(Directory placeRoot, FileSystem fs) {
    final names = <String>{};
    for (final base in [
      Residence.memBase(placeRoot, fs),
      Residence.txBase(placeRoot, fs),
    ]) {
      if (!base.existsSync()) continue;
      for (final e in base.listSync()) {
        if (e is Directory) names.add(fs.path.basename(e.path));
      }
    }
    final sorted = names.toList()..sort();
    return sorted;
  }
}
