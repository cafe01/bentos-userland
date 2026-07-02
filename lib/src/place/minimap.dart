import 'model/place.dart';
import 'habitat_index.dart';

/// A node in the located minimap: either a place (expanded or collapsed) or a
/// synthetic `+N more` sibling-overflow marker.
final class MinimapNode {
  MinimapNode.place(
    this.place, {
    this.isCurrent = false,
    this.collapsed = false,
    this.subtreeCount = 0,
    List<MinimapNode>? children,
  })  : moreCount = 0,
        children = children ?? const [];

  /// The `… (+N more)` overflow placeholder terminating a truncated sibling list.
  MinimapNode.more(this.moreCount)
      : place = null,
        isCurrent = false,
        collapsed = false,
        subtreeCount = 0,
        children = const [];

  /// The place at this node; null iff this is a [MinimapNode.more] placeholder.
  final Place? place;

  /// The "you are here" marker sits on exactly one node.
  final bool isCurrent;

  /// Rendered as `name/… (N places)` — a distant branch folded behind the fog.
  final bool collapsed;

  /// Places hidden inside a [collapsed] branch (inclusive of the branch root).
  final int subtreeCount;

  /// >0 iff this is a sibling-overflow placeholder.
  final int moreCount;

  final List<MinimapNode> children;

  bool get isMore => moreCount > 0;
}

/// The core of `where`: given the habitat index, the current place, and a
/// [radius], produce the located map — the ancestor chain always expanded, the
/// neighborhood expanded to [radius] hops, distant branches collapsed to
/// `name/… (N places)`, and long sibling lists truncated to [siblingLimit] with
/// a `+N more` tail. Pure: index + position + radius → structure. Rendering to
/// text is [MinimapRender]'s job.
///
/// The tuning numbers are defaults, not magic constants — the `where` command
/// exposes [radius] as a flag; the rest are constructor knobs.
final class Minimap {
  const Minimap({this.radius = 1, this.siblingLimit = 4});

  /// Hops around the current place that stay fully expanded (default 1).
  final int radius;

  /// Max sibling places shown before the list truncates to `+N more` (default 4).
  final int siblingLimit;

  /// Build the located map rooted at the habitat root, centered on [current].
  MinimapNode build(HabitatIndex index, Place current) {
    final currentNode = index.nodeFor(current);
    if (currentNode == null) {
      throw ArgumentError('current place is not in the index: ${current.root.path}');
    }

    // The spine: current's path back to the root — always expanded.
    final spine = <String>{current.root.path};
    for (final a in current.ancestors) {
      spine.add(a.root.path);
    }

    // Tree distance from the current node to every node, over parent+child edges.
    final dist = _distances(index, currentNode);

    return _render(index.root, currentNode, spine, dist);
  }

  MinimapNode _render(
    PlaceNode node,
    PlaceNode currentNode,
    Set<String> spine,
    Map<String, int> dist,
  ) {
    final path = node.place.root.path;
    final onSpine = spine.contains(path);
    final d = dist[path] ?? _far;
    final expanded = onSpine || d <= radius;
    final isCurrent = identical(node, currentNode);

    if (!expanded) {
      // A leaf has nothing to fold — show it bare, not `name/… (1 place)`.
      if (node.children.isEmpty) {
        return MinimapNode.place(node.place, isCurrent: isCurrent);
      }
      return MinimapNode.place(
        node.place,
        isCurrent: isCurrent,
        collapsed: true,
        subtreeCount: _subtreeCount(node),
      );
    }

    final kids = node.children;
    final shown = _pickChildren(kids, spine);
    final childNodes = [
      for (final c in shown) _render(c, currentNode, spine, dist),
    ];
    if (shown.length < kids.length) {
      childNodes.add(MinimapNode.more(kids.length - shown.length));
    }
    return MinimapNode.place(
      node.place,
      isCurrent: isCurrent,
      children: childNodes,
    );
  }

  /// Choose which children to show: the first [siblingLimit] in order, but
  /// always keeping the spine-bearing child visible (swapped into the last slot
  /// if it falls past the window) so the path to `you are here` never vanishes.
  List<PlaceNode> _pickChildren(List<PlaceNode> kids, Set<String> spine) {
    if (kids.length <= siblingLimit) return kids;
    final shown = kids.take(siblingLimit).toList();
    final spineChild = kids.where((k) => spine.contains(k.place.root.path));
    if (spineChild.isNotEmpty && !shown.contains(spineChild.first)) {
      shown[shown.length - 1] = spineChild.first;
    }
    return shown;
  }

  int _subtreeCount(PlaceNode node) {
    var n = 1;
    for (final c in node.children) {
      n += _subtreeCount(c);
    }
    return n;
  }

  Map<String, int> _distances(HabitatIndex index, PlaceNode from) {
    final parent = <String, PlaceNode>{};
    _walkParents(index.root, parent);
    final dist = <String, int>{from.place.root.path: 0};
    final queue = <PlaceNode>[from];
    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      final d = dist[n.place.root.path]!;
      final neighbors = <PlaceNode>[
        ...n.children,
        if (parent[n.place.root.path] != null) parent[n.place.root.path]!,
      ];
      for (final m in neighbors) {
        if (dist.containsKey(m.place.root.path)) continue;
        dist[m.place.root.path] = d + 1;
        queue.add(m);
      }
    }
    return dist;
  }

  void _walkParents(PlaceNode node, Map<String, PlaceNode> parent) {
    for (final c in node.children) {
      parent[c.place.root.path] = node;
      _walkParents(c, parent);
    }
  }

  static const _far = 1 << 30;
}
