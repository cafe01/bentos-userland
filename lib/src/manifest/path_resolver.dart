import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// A resolved `<xi:include>` target — the included file's content paired with its
/// canonical path, which doubles as the cycle-detection key.
typedef ResolvedInclude = ({String content, String canonicalPath});

/// Resolves an `<xi:include href=…>` to a file in the tree.
///
/// Two href kinds, tried in ONE order — and the order IS the fix for the
/// historical bug (`Include not found: skill_abstract.xml`):
///
///  1. RELATIVE FILE — `baseDir/href` (e.g. `skill_abstract.xml` beside the
///     particle file that includes it). Tried FIRST.
///  2. FQDN — `anamnesis.faculty` → `faculty/anamnesis/anamnesis.xml`, searched
///     across [_treeRoots] in order, which(1)-style: first root that has it wins.
///
/// A bare `skill_abstract.xml` must resolve as a relative member, not be parsed
/// as an FQDN (`split('.')` → garbage path). Relative-first makes a member
/// include resolve against its package dir before the FQDN attempt.
///
/// All IO goes through the injected [FileSystem] — pass a `MemoryFileSystem` in
/// tests, the real one in `bin/`.
final class PathResolver {
  PathResolver(this._fs, this._treeRoots);

  final FileSystem _fs;
  final List<String> _treeRoots;

  /// Translate an FQDN to its relative tree path, or null if [fqdn] is not a
  /// well-formed FQDN (fewer than two dot-segments). Pure — no IO.
  ///
  /// ONE uniform rule, no per-family special cases: reverse every segment to form
  /// the directory path, and the file is `<first-segment>.xml` — the particle's
  /// own name, NOT a fixed `atom.xml`. A filename that does not prescribe the
  /// type is what lets a directory hold an atom, a molecule, or an organism.
  ///
  ///   alfred.soul              → soul/alfred/alfred.xml
  ///   anamnesis.faculty        → faculty/anamnesis/anamnesis.xml
  ///   swift.coding.craft.skill → skill/craft/coding/swift/swift.xml
  ///   alfred.agent             → agent/alfred/alfred.xml   (the whole organism)
  ///   foo.bar.baz              → baz/bar/foo/foo.xml
  String? fqdnToRelPath(String fqdn) {
    final segs = fqdn.split('.');
    if (segs.length < 2 || segs.any((s) => s.isEmpty)) return null;
    // Reverse: [a, b, c] → [c, b, a]; file = first original segment + .xml
    final reversed = segs.reversed.toList();
    return p.joinAll([...reversed, '${segs.first}.xml']);
  }

  /// The symmetric inverse of [fqdnToRelPath]: a tree-relative particle path back
  /// to its FQDN, or null if [relPath] is not a particle root. Pure — no IO.
  ///
  /// A particle root is either `<dir>/atom.xml` (the canonical convention, FQDN in
  /// the file's `id` attribute) OR `<dir>/<first-segment>.xml` (the named
  /// convention, basename equal to the last directory segment). Both map to the
  /// same FQDN: reverse the directory segments. A file that is neither (an
  /// `xi:include` member like `skill_abstract.xml` or `soul.xml`) is not a particle
  /// root → null.
  ///
  ///   soul/alfred/alfred.xml            → alfred.soul
  ///   skill/craft/coding/swift/swift.xml → swift.coding.craft.skill
  ///   skill/tools/git/atom.xml          → git.tools.skill   (canonical)
  ///   baz/bar/foo/foo.xml               → foo.bar.baz
  ///   skill/craft/coding/dart/skill_abstract.xml → null (a member, not a root)
  String? relPathToFqdn(String relPath) {
    final parts = p.split(relPath);
    if (parts.length < 2) return null;
    final basename = parts.last;
    if (!basename.endsWith('.xml')) return null;
    final stem = basename.substring(0, basename.length - 4);
    final parentDir = parts[parts.length - 2];
    if (stem != 'atom' && stem != parentDir) return null;
    // dirs = all but the last (the file); reverse them to form FQDN
    final dirs = parts.sublist(0, parts.length - 1);
    return dirs.reversed.join('.');
  }

  /// Resolve [href] against [baseDir]: relative-file first, then FQDN against the
  /// tree roots in order. Returns null when neither kind hits (a missing include).
  ResolvedInclude? resolve(String href, String baseDir) {
    // 1. Relative file
    final relFile = _fs.file(p.join(baseDir, href));
    if (relFile.existsSync()) {
      return (
        content: relFile.readAsStringSync(),
        canonicalPath: relFile.path,
      );
    }
    // 2. FQDN which(1)-style across roots. Each root tries the named convention
    //    (<name>.xml) first, then the canonical atom.xml in the same dir — so a dir
    //    holding both prefers the named file, and a skill that only ships atom.xml
    //    still resolves.
    final relPath = fqdnToRelPath(href);
    if (relPath != null) {
      final atomVariant = p.join(p.dirname(relPath), 'atom.xml');
      for (final root in _treeRoots) {
        for (final candidate in [relPath, atomVariant]) {
          final f = _fs.file(p.join(root, candidate));
          if (f.existsSync()) {
            return (content: f.readAsStringSync(), canonicalPath: f.path);
          }
        }
      }
    }
    return null;
  }
}
