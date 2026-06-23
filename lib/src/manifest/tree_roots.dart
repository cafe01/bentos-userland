import 'package:file/file.dart';

/// Resolves the ordered list of tree roots the resolver searches, which(1)-style.
///
/// Tree roots are a SEARCH PATH, the same model as `.claude`: explicit overrides
/// first, then implicit defaults discovered automatically. Nobody sets a variable
/// by hand to make `manifest <fqdn>` work — the implicit roots are always there.
///
/// ORDER (which(1) precedence — first hit wins downstream):
///   1. EXPLICIT — `env['BENTOS_TREE_PATH']`, colon-separated, in order, dropping
///      empties. The override/addition channel. Included verbatim, existence NOT
///      checked (an explicit root is the caller's assertion; the resolver checks
///      per-file anyway).
///   2. PROJECT (implicit, appended) — the nearest `.bentos/tree` found by walking
///      UP from [cwd] to the filesystem root, like git finding `.git`. The first
///      ancestor whose `.bentos/tree` directory exists wins; at most one. Works
///      from any subdirectory of a project.
///   3. USER (implicit, appended) — `${env['HOME']}/.bentos/tree`, when HOME is set
///      and that directory exists.
///
/// Implicit roots are appended only when their directory EXISTS (a missing default
/// must never appear and shadow nothing). All IO goes through [fs] — pass a
/// `MemoryFileSystem` in tests, a `LocalFileSystem` in `bin/` with the real cwd and
/// `Platform.environment`.
///
/// NUANCES (Café):
///  - The implicit defaults are ADDED AT THE END, after the env-var roots. The
///    variable survives; it just no longer the only source.
///  - `.bentos/tree` is NOT a canonical home — it is one more root among equals,
///    exactly one project-level place and one user-level place that get searched.
///  - PROJECT discovery is walk-UP (any subdir works), USER is a fixed path.
List<String> resolveTreeRoots(FileSystem fs, String cwd, Map<String, String> env) {
  final roots = <String>[];

  // 1. EXPLICIT — BENTOS_TREE_PATH, colon-split, empties dropped, verbatim.
  final envPath = env['BENTOS_TREE_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    roots.addAll(envPath.split(':').where((s) => s.isNotEmpty));
  }

  // 2. PROJECT — walk-up from cwd looking for .bentos/tree.
  var dir = cwd;
  while (true) {
    final candidate = '$dir/.bentos/tree';
    if (fs.directory(candidate).existsSync()) {
      roots.add(candidate);
      break;
    }
    final parent = fs.path.dirname(dir);
    if (parent == dir) break; // reached fs root
    dir = parent;
  }

  // 3. USER — $HOME/.bentos/tree when HOME is set and dir exists.
  final home = env['HOME'];
  if (home != null && home.isNotEmpty) {
    final userTree = '$home/.bentos/tree';
    if (fs.directory(userTree).existsSync()) {
      roots.add(userTree);
    }
  }

  return roots;
}
