import 'package:file/file.dart';

import 'path_resolver.dart';

/// Lists particles in the tree by FQDN — the engine under `manifest ls <pattern>`.
///
/// THE JOB. Walk every tree root, find each particle file, map it back to its
/// FQDN, and keep the ones the pattern matches. Output is FQDNs, one per line,
/// sorted — a plain stream the shell pipes (`manifest ls '*.skill' | grep …`);
/// `ls` emits, you filter (no built-in `--grep`).
///
/// FILE → FQDN. A particle file is `<dir>/<first-segment>.xml`. The reverse of
/// [PathResolver.fqdnToRelPath]: reverse the directory segments to get the FQDN,
/// and only count a file whose basename matches its own first segment
/// (`baz/bar/foo/foo.xml` → `foo.bar.baz`; `baz/bar/foo/other.xml` is NOT a
/// particle root — skip it, it is an `xi:include` member like `skill_abstract.xml`).
/// The mapping authority is [PathResolver.relPathToFqdn] — never re-derived here.
///
/// WILDCARD, NOT GLOB. Matching is the pure top-level [fqdnMatchesWildcard] —
/// dot-notation wildcard filtering over atom IDs, not filepath-glob semantics.
/// Kept pure and separate so it carries its own contract tests, blind to the
/// filesystem.
///
/// PURITY OF THE WALK. All IO flows through the injected [FileSystem]; inject a
/// `MemoryFileSystem` and the lister is fully testable. Roots are searched and
/// results unioned (a particle present in two roots lists once).
final class TreeLister {
  TreeLister(this._fs, this._treeRoots);

  final FileSystem _fs;
  final List<String> _treeRoots;

  /// All particle FQDNs across the roots whose name matches [pattern], sorted
  /// and de-duplicated.
  List<String> list(String pattern) {
    final resolver = PathResolver(_fs, _treeRoots);
    final seen = <String>{};
    for (final root in _treeRoots) {
      final dir = _fs.directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final abs = entity.path;
        if (!abs.endsWith('.xml')) continue;
        // Make path tree-relative by stripping the root prefix.
        var rel = abs.startsWith(root) ? abs.substring(root.length) : abs;
        if (rel.startsWith('/')) rel = rel.substring(1);
        final fqdn = resolver.relPathToFqdn(rel);
        if (fqdn == null) continue;
        if (fqdnMatchesWildcard(fqdn, pattern)) seen.add(fqdn);
      }
    }
    return seen.toList()..sort();
  }
}

/// Does [fqdn] match [pattern]? Dot-notation wildcard filtering — NOT
/// filepath-glob semantics:
///
/// - `*` matches any run (zero or more) of *whole* dot-segments — never a
///   partial segment (`alfred.s*` is not a wildcard; the `*` there is dead,
///   only `alfred.s*` itself, literally, would match, which is never useful).
/// - `{a,b,...}` brace-expands to the union of one pattern per alternative,
///   and composes with `*` (`*.{agent,soul}`).
/// - Bare `*` (or the default with no pattern) matches everything.
///
/// There is no second wildcard for "any run of segments" — `*` already means
/// that; `**` from filepath-glob is dropped entirely, not recognized.
///
/// Pure — no IO, no tree knowledge.
///
///   fqdnMatchesWildcard('alfred.soul', 'soul')            → false (exact, no wildcard)
///   fqdnMatchesWildcard('alfred.soul', '*.soul')           → true
///   fqdnMatchesWildcard('a.b.c.skill', '*.skill')          → true
///   fqdnMatchesWildcard('alfred.agent', '*.{agent,soul}')  → true
bool fqdnMatchesWildcard(String fqdn, String pattern) {
  final fsegs = fqdn.split('.');
  return _expandBraces(pattern).any((p) => _matchSegs(fsegs, 0, p.split('.'), 0));
}

/// Expands one `{a,b,...}` group into its alternatives; a pattern with no
/// braces returns unchanged as the sole alternative. Only one brace group is
/// expected per pattern.
List<String> _expandBraces(String pattern) {
  final open = pattern.indexOf('{');
  if (open == -1) return [pattern];
  final close = pattern.indexOf('}', open);
  if (close == -1) return [pattern];
  final prefix = pattern.substring(0, open);
  final suffix = pattern.substring(close + 1);
  final alternatives = pattern.substring(open + 1, close).split(',');
  return alternatives.map((a) => '$prefix$a$suffix').toList();
}

bool _matchSegs(List<String> fsegs, int fi, List<String> psegs, int pi) {
  if (pi == psegs.length) return fi == fsegs.length;
  if (fi == fsegs.length) {
    // only matches if every remaining pattern segment is the wildcard
    return psegs.sublist(pi).every((s) => s == '*');
  }
  final p = psegs[pi];
  if (p == '*') {
    // consume zero or more whole fqdn segments
    for (var skip = 0; skip <= fsegs.length - fi; skip++) {
      if (_matchSegs(fsegs, fi + skip, psegs, pi + 1)) return true;
    }
    return false;
  }
  if (p == fsegs[fi]) {
    return _matchSegs(fsegs, fi + 1, psegs, pi + 1);
  }
  return false;
}
