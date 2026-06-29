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
  /// A particle root is `<dir>/<last-segment>.xml` — the named convention, basename
  /// equal to the last directory segment. Map to its FQDN by reversing the
  /// directory segments. A file that is not (an `xi:include` member like
  /// `skill_abstract.xml` or `soul.xml`) is not a particle root → null.
  ///
  ///   soul/alfred/alfred.xml            → alfred.soul
  ///   skill/craft/coding/swift/swift.xml → swift.coding.craft.skill
  ///   baz/bar/foo/foo.xml               → foo.bar.baz
  ///   skill/craft/coding/dart/skill_abstract.xml → null (a member, not a root)
  String? relPathToFqdn(String relPath) {
    final parts = p.split(relPath);
    if (parts.length < 2) return null;
    final basename = parts.last;
    if (!basename.endsWith('.xml')) return null;
    final stem = basename.substring(0, basename.length - 4);
    final parentDir = parts[parts.length - 2];
    if (stem != parentDir) return null;
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
    // 2. FQDN which(1)-style across roots. ONE filename: the named convention
    //    (`<first-segment>.xml`, basename == last directory segment). First root
    //    that has it wins. No `atom.xml` fallback — the file's name IS its identity.
    final relPath = fqdnToRelPath(href);
    if (relPath != null) {
      for (final root in _treeRoots) {
        final f = _fs.file(p.join(root, relPath));
        if (f.existsSync()) {
          return (content: f.readAsStringSync(), canonicalPath: f.path);
        }
      }
    }
    return null;
  }
}
