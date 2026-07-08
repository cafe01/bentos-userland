import 'package:file/file.dart';

import 'model/place.dart';
import 'place_resolver.dart';
import 'residence.dart';

/// A node in the habitat tree: a place and its nested child places, sorted by
/// name.
final class PlaceNode {
  PlaceNode(this.place);

  final Place place;
  final List<PlaceNode> children = [];
}

/// The whole-machine index of places: one scan from `/` for `.place/` markers,
/// built into an in-memory tree. Every navigator verb (`where`, `tree`, `info`,
/// `who`) reads this one structure — none re-derives the tree per query.
///
/// Two invariants keep it honest: the implicit places (`/`, home) materialize
/// even markerless, so you are never nowhere; and a sibling worktree (a
/// timeline, control-plane and untracked) carries no marker of its own, so the
/// naive scan already folds `(place, timeline)` into one spatial node.
final class HabitatIndex {
  HabitatIndex._(this.root, this._byPath);

  /// The machine root (`/`), always present.
  final PlaceNode root;

  final Map<String, PlaceNode> _byPath;

  /// The node for [place], or null if it is not in the index.
  PlaceNode? nodeFor(Place place) => _byPath[place.root.path];

  /// Every place in the index, unordered.
  Iterable<Place> get places => _byPath.values.map((n) => n.place);

  /// Non-hidden directory basenames that never hold a place and are pruned
  /// wherever they appear — dependency dumps, build outputs. (Hidden dirs are
  /// pruned wholesale by the descent; these are the visible noise.)
  static const defaultPruneNames = <String>{
    'node_modules',
    'build',
  };

  /// Scan [resolver]'s filesystem from [from] (default `/`) and build the tree.
  ///
  /// [pruneRoots] is a set of absolute directory paths never descended into —
  /// the platform-native system roots (`/System`, `/usr`, `/proc`, …), which
  /// hold no places and otherwise dominate a whole-machine walk. It prunes by
  /// *absolute path*, not basename, so a place at a non-system child of `/` is
  /// still reached. [pruneNames] prunes by basename anywhere (default:
  /// [defaultPruneNames]). The caller (which reads the platform) supplies
  /// [pruneRoots]; the scan itself stays filesystem-only and hermetic.
  static HabitatIndex scan(
    PlaceResolver resolver, {
    String from = '/',
    Set<String> pruneRoots = const {},
    Set<String> pruneNames = defaultPruneNames,
  }) {
    final fs = resolver.fs;
    final rootPath = fs.path.normalize(fs.path.absolute(from));
    final paths = <String>{};

    // The implicit terminals materialize even unmarked.
    paths.add(rootPath);
    if (fs.directory(resolver.home).existsSync()) paths.add(resolver.home);

    // Walk the tree for every `.place/` marker, never descending into one.
    // Paths are kept absolute throughout — a filesystem's listSync may hand
    // back entries relative to the scan root, so we rejoin against the known
    // absolute parent rather than trust the child's own path string.
    final stack = <String>[rootPath];
    while (stack.isNotEmpty) {
      final dirPath = stack.removeLast();
      final dir = fs.directory(dirPath);
      if (Residence.isMarked(dir, fs)) paths.add(dirPath);
      // A whole-machine scan meets unreadable dirs, special files, and broken
      // symlinks — a place is found by descent, not by force, so an unlistable
      // directory is skipped, never fatal. Symlinks are not followed (a
      // timeline is a sibling worktree, not a place reached through a link).
      final List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        if (e is! Directory) continue;
        final base = fs.path.basename(e.path);
        // Hidden dirs are pruned wholesale — a `.place/` inside one is a place
        // its owner explicitly hid. (The scan root itself is never a child
        // here, so `place tree path/to/.hidden` still works: it starts from
        // within.) This subsumes `.place`, `.git`, `.pub-cache`, `.cache`, …
        if (base.startsWith('.')) continue;
        if (pruneNames.contains(base)) continue;
        final childPath = fs.path.join(dirPath, base);
        if (pruneRoots.contains(childPath)) continue;
        stack.add(childPath);
      }
    }

    // Materialize a Place per path, then wire each to its nearest place ancestor.
    final byPath = <String, PlaceNode>{
      for (final p in paths) p: PlaceNode(resolver.enclosing(p)),
    };
    PlaceNode? rootNode;
    for (final node in byPath.values) {
      final ancestors = node.place.ancestors;
      final parentPath = ancestors.isEmpty ? null : ancestors.first.root.path;
      final parent = parentPath == null ? null : byPath[parentPath];
      if (parent == null) {
        rootNode = node;
      } else {
        parent.children.add(node);
      }
    }
    for (final node in byPath.values) {
      node.children.sort((a, b) => a.place.name.compareTo(b.place.name));
    }

    return HabitatIndex._(rootNode!, byPath);
  }
}
