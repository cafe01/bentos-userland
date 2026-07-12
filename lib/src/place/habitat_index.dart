import 'dart:io';

import 'package:path/path.dart' as p;

import 'home_ambient.dart';
import 'place.dart';

/// A node in the habitat tree: a place and its nested child places, sorted by
/// name.
final class PlaceNode {
  PlaceNode(this.place);

  final Place place;
  final List<PlaceNode> children = [];
}

/// An in-memory tree of places, built from a filesystem scan for `.place/`
/// markers. Two entry points, two cost classes: [scan] walks a subtree
/// wholesale (from `/` for the whole machine, or from any place for `place
/// tree`); [neighborhood] bounds the walk to the habitat around a location for
/// `place where`, so a `where` from deep in the habitat never walks the
/// machine's unmarked voids (`/var`, the home's sibling SDK dumps) to find
/// markers that only ever live in the habitat.
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

  /// Scan from [from] (default `/`) and build the tree.
  ///
  /// [pruneRoots] is a set of absolute directory paths never descended into —
  /// the platform-native system roots (`/System`, `/usr`, `/proc`, …), which
  /// hold no places and otherwise dominate a whole-machine walk. It prunes by
  /// *absolute path*, not basename, so a place at a non-system child of `/` is
  /// still reached. [pruneNames] prunes by basename anywhere (default:
  /// [defaultPruneNames]). The caller (which reads the platform) supplies
  /// [pruneRoots]; the scan itself stays filesystem-only and hermetic.
  ///
  /// [includeImplicitHome] injects the logged-in home as an extra implicit
  /// terminal — right for a whole-machine scan (so you are never nowhere),
  /// wrong for a subtree scan ([from] below `/`), where the scan root is the
  /// terminal and a stray home node above it would pollute the tree. A
  /// subtree scan (`place tree <place>`) passes false: it wants only the
  /// places nested under [from], not the machine's home.
  static HabitatIndex scan({
    String from = '/',
    Set<String> pruneRoots = const {},
    Set<String> pruneNames = defaultPruneNames,
    bool includeImplicitHome = true,
  }) {
    final rootPath = p.normalize(p.absolute(from));
    final paths = <String>{};

    // The implicit terminals materialize even unmarked.
    paths.add(rootPath);
    if (includeImplicitHome && Directory(ambientHome).existsSync()) {
      paths.add(ambientHome);
    }

    // Walk the tree for every `.place/` marker, never descending into one.
    // Each stack frame carries the `.gitignore` rules accumulated from the
    // root down to it, so a nested `.gitignore` layers onto its ancestors'
    // exactly as git itself resolves ignores.
    final stack = <(String, List<_GitignoreRule>)>[(rootPath, const [])];
    while (stack.isNotEmpty) {
      final (dirPath, inherited) = stack.removeLast();
      if (_isMarkedDir(dirPath)) paths.add(dirPath);
      // A whole-machine scan meets unreadable dirs, special files, and broken
      // symlinks — a place is found by descent, not by force, so an unlistable
      // directory is skipped, never fatal. Symlinks are not followed (a
      // timeline is a sibling worktree, not a place reached through a link).
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(dirPath).listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      final rules = [...inherited, ..._parseGitignore(dirPath)];
      for (final e in entries) {
        if (e is! Directory) continue;
        final base = p.basename(e.path);
        // Hidden dirs are pruned wholesale — a `.place/` inside one is a place
        // its owner explicitly hid. (The scan root itself is never a child
        // here, so `place tree path/to/.hidden` still works: it starts from
        // within.) This subsumes `.place`, `.git`, `.pub-cache`, `.cache`, …
        if (base.startsWith('.')) continue;
        if (pruneNames.contains(base)) continue;
        final childPath = p.join(dirPath, base);
        if (pruneRoots.contains(childPath)) continue;
        if (_isGitignored(childPath, rules)) continue;
        stack.add((childPath, rules));
      }
    }

    // Materialize a Place per path, then wire each to its nearest place ancestor.
    final byPath = <String, PlaceNode>{
      for (final path in paths) path: PlaceNode(Place(path)),
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

  /// The located index for `where`: bounded to the habitat, never the whole
  /// machine. Places are curated and sparse, and they cluster — the whole
  /// habitat nests under one top-level place — yet a scan from `/` walked every
  /// unmarked void on the machine (`/var`, the home's sibling trees, an SDK
  /// dump of tens of thousands of directories) to find markers that only ever
  /// live in the habitat. This scans only the subtree under the **habitat
  /// root** — the topmost real (marked) place enclosing [current] — and grafts
  /// the implicit ancestors (the home, the machine root) above it as
  /// pass-through context: resolved so the map still shows where you sit on the
  /// machine, but never descended into.
  ///
  /// When the spine carries no real place (a cwd sitting in a bare void under
  /// the home or the machine root), it falls back to scanning [current]'s own
  /// resolved place — strictly less work than a walk from `/`, never more.
  static HabitatIndex neighborhood(
    Place current, {
    Set<String> pruneRoots = const {},
    Set<String> pruneNames = defaultPruneNames,
  }) {
    // The habitat root: the highest marked place enclosing us. The ancestor
    // chain runs nearest→root, so the last non-implicit entry is the topmost
    // real place; absent any, [current]'s own resolved place is the root.
    var habitatRoot = current;
    for (final ancestor in current.ancestors) {
      if (!ancestor.isImplicit) habitatRoot = ancestor;
    }

    // One bounded scan of the habitat subtree — the implicit home above it is
    // context, grafted next, not a scan terminal here.
    final sub = scan(
      from: habitatRoot.root.path,
      pruneRoots: pruneRoots,
      pruneNames: pruneNames,
      includeImplicitHome: false,
    );

    // Graft the implicit ancestors above the habitat root as pass-through
    // nodes: …the machine → home → habitat, each resolved but never walked.
    final byPath = {...sub._byPath};
    var rootNode = sub.root;
    for (final ancestor in habitatRoot.ancestors) {
      final node = byPath.putIfAbsent(ancestor.root.path, () => PlaceNode(ancestor));
      node.children.add(rootNode);
      rootNode = node;
    }

    return HabitatIndex._(rootNode, byPath);
  }

  /// True iff [dirPath] is itself a marked place — a single-stat probe on the
  /// directory, never a handle resolution: the scan calls this on every
  /// directory on the machine, so it must not walk up to the nearest enclosing
  /// place (which [Place.isImplicit]/[Place.root] would do on every unmarked
  /// void, making the whole scan O(depth)). The `.place/…` literal stays
  /// Place's secret behind [Place.isMarkedAt].
  static bool _isMarkedDir(String dirPath) => Place.isMarkedAt(dirPath);

  /// The `.gitignore` rules declared directly in [dirPath], or none if it has
  /// no `.gitignore` (or it isn't readable). Deliberately pragmatic: whole
  /// blank/comment/negation lines are skipped, and matching is directory-level
  /// (see [_GitignoreRule]) — the goal is prune-not-descend, not full
  /// gitignore fidelity.
  static List<_GitignoreRule> _parseGitignore(String dirPath) {
    final file = File(p.join(dirPath, '.gitignore'));
    final List<String> lines;
    try {
      if (!file.existsSync()) return const [];
      lines = file.readAsLinesSync();
    } on FileSystemException {
      return const [];
    }
    final rules = <_GitignoreRule>[];
    for (final raw in lines) {
      var pattern = raw.trim();
      if (pattern.isEmpty || pattern.startsWith('#') || pattern.startsWith('!')) {
        continue;
      }
      if (pattern.endsWith('/')) pattern = pattern.substring(0, pattern.length - 1);
      if (pattern.isEmpty) continue;
      // A pattern with an interior `/` is anchored to the `.gitignore`'s own
      // directory (git semantics); a bare name (`build`, `*.log`) matches
      // that basename at any depth beneath it.
      final anchored = pattern.contains('/');
      if (pattern.startsWith('/')) pattern = pattern.substring(1);
      rules.add(_GitignoreRule(dirPath, _globToRegExp(pattern), anchored));
    }
    return rules;
  }

  /// True iff [childPath] matches any of [rules] — checked against the full
  /// path relative to the declaring `.gitignore`'s directory when [anchored],
  /// or against the bare basename otherwise.
  static bool _isGitignored(String childPath, List<_GitignoreRule> rules) {
    for (final rule in rules) {
      final target = rule.anchored
          ? p.relative(childPath, from: rule.baseDir)
          : p.basename(childPath);
      if (rule.regex.hasMatch(target)) return true;
    }
    return false;
  }

  /// Translates a `.gitignore` glob (`*` and `?`, no path separator meaning)
  /// into a whole-string [RegExp]. No `**` support — pragmatic, not exhaustive.
  static RegExp _globToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (final ch in pattern.split('')) {
      switch (ch) {
        case '*':
          buffer.write('[^/]*');
        case '?':
          buffer.write('[^/]');
        default:
          buffer.write(RegExp.escape(ch));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}

/// One `.gitignore` line, compiled: [baseDir] is the directory the declaring
/// `.gitignore` lives in; [anchored] means the pattern is relative to
/// [baseDir] (matched against the full relative path), otherwise it matches
/// the bare basename at any depth beneath [baseDir].
final class _GitignoreRule {
  _GitignoreRule(this.baseDir, this.regex, this.anchored);

  final String baseDir;
  final RegExp regex;
  final bool anchored;
}
