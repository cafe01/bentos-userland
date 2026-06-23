import 'package:file/file.dart';

import 'path_resolver.dart';

/// Lists particles in the tree by FQDN — the engine under `manifest ls <glob>`.
///
/// THE JOB. Walk every tree root, find each particle file, map it back to its
/// FQDN, and keep the ones the glob matches. Output is FQDNs, one per line,
/// sorted — a plain stream the shell pipes (`manifest ls 'skill.**' | grep …`);
/// `ls` emits, you filter (no built-in `--grep`).
///
/// FILE → FQDN. A particle file is `<dir>/<first-segment>.xml`. The reverse of
/// [PathResolver.fqdnToRelPath]: reverse the directory segments to get the FQDN,
/// and only count a file whose basename matches its own first segment
/// (`baz/bar/foo/foo.xml` → `foo.bar.baz`; `baz/bar/foo/other.xml` is NOT a
/// particle root — skip it, it is an `xi:include` member like `skill_abstract.xml`).
/// The mapping authority is [PathResolver.relPathToFqdn] — never re-derived here.
///
/// GLOB. Matching is the pure top-level [fqdnMatchesGlob] — `*` matches within one
/// dot-segment, `**` matches across segments (attracts-match syntax). Kept pure
/// and separate so it carries its own contract tests, blind to the filesystem.
///
/// PURITY OF THE WALK. All IO flows through the injected [FileSystem]; inject a
/// `MemoryFileSystem` and the lister is fully testable. Roots are searched and
/// results unioned (a particle present in two roots lists once).
final class TreeLister {
  TreeLister(this._fs, this._treeRoots);

  final FileSystem _fs;
  final List<String> _treeRoots;

  /// All particle FQDNs across the roots whose name matches [glob], sorted and
  /// de-duplicated.
  List<String> list(String glob) {
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
        if (fqdnMatchesGlob(fqdn, glob)) seen.add(fqdn);
      }
    }
    return seen.toList()..sort();
  }
}

/// Does [fqdn] match [glob]? `*` matches within a single dot-segment, `**` matches
/// any number of segments. Pure — no IO, no tree knowledge.
///
///   fqdnMatchesGlob('alfred.soul', 'soul')          → false (exact, no wildcard)
///   fqdnMatchesGlob('alfred.soul', '*.soul')        → true
///   fqdnMatchesGlob('a.b.c.skill', 'skill.**')      → (depends on segment order)
bool fqdnMatchesGlob(String fqdn, String glob) {
  final fsegs = fqdn.split('.');
  final gsegs = glob.split('.');
  return _matchSegs(fsegs, 0, gsegs, 0);
}

bool _matchSegs(List<String> fsegs, int fi, List<String> gsegs, int gi) {
  if (gi == gsegs.length) return fi == fsegs.length;
  if (fi == fsegs.length) {
    // only matches if remaining glob segs are all '**'
    return gsegs.sublist(gi).every((s) => s == '**');
  }
  final g = gsegs[gi];
  if (g == '**') {
    // try consuming 0 or more fqdn segments
    for (var skip = 0; skip <= fsegs.length - fi; skip++) {
      if (_matchSegs(fsegs, fi + skip, gsegs, gi + 1)) return true;
    }
    return false;
  }
  if (g == '*' || g == fsegs[fi]) {
    return _matchSegs(fsegs, fi + 1, gsegs, gi + 1);
  }
  return false;
}
