// THROWAWAY migration (out-of-band, not part of the system).
// Legacy bare `place.yaml` marker  ->  `.place/place.yaml` residence marker.
//
// The greenfield Place resolver only recognizes a `.place/` directory as a
// marker; this relocates every legacy bare `place.yaml` into one. Must run
// BEFORE the new organ goes live.
//
// Dry-run by DEFAULT. Pass --write to touch disk. --root points at the tree
// (default: cwd) so it can be aimed at a fixture copy.
//
//   dart run script/migrate/migrate_place.dart --root /tmp/fixture          # plan
//   dart run script/migrate/migrate_place.dart --root /tmp/fixture --write  # apply
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main(List<String> argv) {
  final write = argv.contains('--write');
  final root = _flag(argv, '--root') ?? Directory.current.path;

  final rootDir = Directory(root);
  if (!rootDir.existsSync()) {
    stderr.writeln('root does not exist: $root');
    exit(2);
  }

  final markers = <File>[];
  for (final e in rootDir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || p.basename(e.path) != 'place.yaml') continue;
    final path = e.path;
    // skip already-migrated markers and vcs/dep noise
    if (path.contains('${Platform.pathSeparator}.place${Platform.pathSeparator}')) continue;
    if (path.contains('${Platform.pathSeparator}.git${Platform.pathSeparator}')) continue;
    if (path.contains('${Platform.pathSeparator}node_modules${Platform.pathSeparator}')) continue;
    markers.add(e);
  }
  markers.sort((a, b) => a.path.compareTo(b.path));

  var moved = 0, skipped = 0, broken = 0;
  for (final f in markers) {
    final dir = p.dirname(f.path);
    final dotPlace = Directory(p.join(dir, '.place'));
    final dst = p.join(dotPlace.path, 'place.yaml');
    final rel = p.relative(f.path, from: root);

    final brokenYaml = _isBroken(f);
    if (brokenYaml) broken++;
    final flag = brokenYaml ? ' [BROKEN yaml — moved as-is, resolver degrades to defaults]' : '';

    if (File(dst).existsSync()) {
      print('SKIP  $rel  (.place/place.yaml already present)');
      skipped++;
      continue;
    }

    print('MOVE  $rel  ->  ${p.relative(dst, from: root)}$flag');
    moved++;

    if (write) {
      dotPlace.createSync(recursive: true);
      f.renameSync(dst);
    }
  }

  print('');
  print('${write ? "APPLIED" : "DRY-RUN"}: '
      '$moved to move, $skipped skipped, $broken broken-yaml among them '
      '(${markers.length} markers scanned).');
  if (!write && moved > 0) print('Re-run with --write to apply.');
}

/// True when the legacy `place.yaml` fails to parse (the two known campus cases:
/// unquoted `description:` values containing a colon). Non-fatal — flagged only.
bool _isBroken(File f) {
  try {
    loadYaml(f.readAsStringSync());
    return false;
  } catch (_) {
    return true;
  }
}

String? _flag(List<String> argv, String name) {
  final i = argv.indexOf(name);
  if (i >= 0 && i + 1 < argv.length) return argv[i + 1];
  for (final a in argv) {
    if (a.startsWith('$name=')) return a.substring(name.length + 1);
  }
  return null;
}
