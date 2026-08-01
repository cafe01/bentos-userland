import 'package:path/path.dart' as p;

import '../minimap.dart';
import '../place.dart';

/// Renders a [MinimapNode] tree to the RPG-minimap ASCII of `place where`: the
/// habitat root as a header, its subtree drawn with `├──`/`└──` connectors, the
/// `◄ you are here` marker on the current node, distant branches folded to
/// `path/… (N places)`, and sibling overflow shown as `… (+N more)`.
///
/// The tree is a filesystem folder tree first: each node's label is its REAL
/// path segment relative to its place-parent (the machine root shows its
/// absolute `/`), so the map tells you where you are on disk — the void
/// directories between places included. A place's metadata (name, description)
/// rides as an annotation *after* the path, never in place of it.
final class MinimapRender {
  const MinimapRender();

  static const marker = '◄ you are here';

  String render(MinimapNode root) {
    final buf = StringBuffer()..writeln(_label(root, null));
    _children(root, '', buf);
    return buf.toString().trimRight();
  }

  void _children(MinimapNode node, String prefix, StringBuffer buf) {
    final parentPath = node.place?.root.path;
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final last = i == node.children.length - 1;
      final connector = last ? '└── ' : '├── ';
      buf.writeln('$prefix$connector${_label(child, parentPath)}');
      _children(child, prefix + (last ? '    ' : '│   '), buf);
    }
  }

  String _label(MinimapNode node, String? parentPath) {
    if (node.isMore) return '… (+${node.moreCount} more)';

    final place = node.place!;
    final path = place.root.path;
    // The real filesystem path: relative to the place-parent (which may skip
    // void directories, so the segment can carry more than one component), or
    // the absolute path at the map's root.
    final segment = parentPath == null ? path : p.relative(path, from: parentPath);

    if (node.collapsed) {
      final noun = node.subtreeCount == 1 ? 'place' : 'places';
      return '$segment/… (${node.subtreeCount} $noun)';
    }

    final buf = StringBuffer(segment);
    if (segment != '/' && node.children.isNotEmpty) buf.write('/');

    if (place.isImplicit) {
      buf.write(path == '/' ? '  (the machine)' : '  (home)');
    } else {
      final meta = _meta(place);
      if (meta != null) buf.write('  · $meta');
    }

    if (node.isCurrent) buf.write('  $marker');
    return buf.toString();
  }

  /// The place's metadata annotation: its declared name (only when it differs
  /// from the folder — else the folder already IS the name) followed by its
  /// description. Null when the place declares neither beyond its folder name.
  String? _meta(Place place) {
    final base = p.basename(place.root.path);
    final name = place.name;
    final parts = <String>[
      if (name != base) name,
      ?place.description,
    ];
    return parts.isEmpty ? null : parts.join(' — ');
  }
}
