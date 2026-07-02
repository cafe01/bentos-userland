import '../habitat_index.dart';

/// Renders a habitat subtree for `place tree`: full recursive expansion from a
/// root [PlaceNode], every place shown. `-t`/[topologyOnly] drops the
/// descriptions, leaving paths only — for token-tight contexts like the wake
/// hook.
final class TreeRender {
  const TreeRender({this.topologyOnly = false});

  final bool topologyOnly;

  String render(PlaceNode root) {
    final buf = StringBuffer()..writeln(_label(root));
    _children(root, '', buf);
    return buf.toString().trimRight();
  }

  void _children(PlaceNode node, String prefix, StringBuffer buf) {
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final last = i == node.children.length - 1;
      buf.writeln('$prefix${last ? '└── ' : '├── '}${_label(child)}');
      _children(child, prefix + (last ? '    ' : '│   '), buf);
    }
  }

  String _label(PlaceNode node) {
    // Every place is a directory — always slash-terminated, leaf or not.
    final name = '${node.place.name}/';
    if (topologyOnly) return name;
    final desc = node.place.description;
    return desc == null ? name : '$name   — $desc';
  }
}
