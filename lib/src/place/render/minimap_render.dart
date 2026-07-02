import '../minimap.dart';

/// Renders a [MinimapNode] tree to the RPG-minimap ASCII of `place where`: the
/// habitat root as a header, its subtree drawn with `├──`/`└──` connectors, the
/// `◄ you are here` marker on the current node, distant branches folded to
/// `name/… (N places)`, and sibling overflow shown as `… (+N more)`.
final class MinimapRender {
  const MinimapRender();

  static const marker = '◄ you are here';

  String render(MinimapNode root) {
    final buf = StringBuffer()..writeln(_label(root));
    _children(root, '', buf);
    return buf.toString().trimRight();
  }

  void _children(MinimapNode node, String prefix, StringBuffer buf) {
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final last = i == node.children.length - 1;
      final connector = last ? '└── ' : '├── ';
      buf.writeln('$prefix$connector${_label(child)}');
      _children(child, prefix + (last ? '    ' : '│   '), buf);
    }
  }

  String _label(MinimapNode node) {
    if (node.isMore) return '… (+${node.moreCount} more)';

    final place = node.place!;
    if (node.collapsed) {
      final noun = node.subtreeCount == 1 ? 'place' : 'places';
      return '${place.name}/… (${node.subtreeCount} $noun)';
    }

    final buf = StringBuffer(place.name);
    if (node.children.isNotEmpty) buf.write('/');
    final hint = _implicitHint(node);
    if (hint != null) buf.write('  ($hint)');
    if (node.isCurrent) buf.write('  $marker');
    return buf.toString();
  }

  String? _implicitHint(MinimapNode node) {
    final place = node.place!;
    if (!place.isImplicit) return null;
    return place.root.path == '/' ? 'the machine' : 'home';
  }
}
