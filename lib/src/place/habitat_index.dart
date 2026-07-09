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

  /// Scan from [from] (default `/`) and build the tree.
  ///
  /// [pruneRoots] is a set of absolute directory paths never descended into —
  /// the platform-native system roots (`/System`, `/usr`, `/proc`, …), which
  /// hold no places and otherwise dominate a whole-machine walk. It prunes by
  /// *absolute path*, not basename, so a place at a non-system child of `/` is
  /// still reached. [pruneNames] prunes by basename anywhere (default:
  /// [defaultPruneNames]). The caller (which reads the platform) supplies
  /// [pruneRoots]; the scan itself stays filesystem-only and hermetic.
  static HabitatIndex scan({
    String from = '/',
    Set<String> pruneRoots = const {},
    Set<String> pruneNames = defaultPruneNames,
  }) {
    final rootPath = p.normalize(p.absolute(from));
    final paths = <String>{};

    // The implicit terminals materialize even unmarked.
    paths.add(rootPath);
    if (Directory(ambientHome).existsSync()) paths.add(ambientHome);

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

  /// True iff [dirPath] is itself a marked place — probed through [Place],
  /// never by constructing the `.place/…` literal directly: a handle anchored
  /// at [dirPath] resolves to itself, non-implicit, iff the marker sits right
  /// there.
  static bool _isMarkedDir(String dirPath) {
    final place = Place(dirPath);
    return !place.isImplicit && place.root.path == dirPath;
  }

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
