import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The on-disk half of the installer: where versions land, and the link swap
/// that makes an install atomic and a rollback free.
///
/// ```
/// <home>/versions/<stream>/<version>/bin/<name>   the artifacts, immutable
/// <home>/versions/<stream>/current -> <version>   one link, swapped by rename
/// <home>/versions/<stream>/previous -> <version>  what rollback goes back to
/// <prefix>/<name> -> ../versions/<stream>/current/bin/<name>
/// ```
///
/// Nothing is ever overwritten in place. The names on the PATH point *through*
/// `current`, so one rename moves a whole userland from one version to the next
/// and a network failure mid-install cannot leave the machine holding half of
/// one.
final class VersionStore {
  const VersionStore({required this.home, required this.prefix});

  final String home;
  final String prefix;

  String streamDir(String stream) => p.join(home, 'versions', stream);
  String versionDir(String stream, String version) => p.join(streamDir(stream), version);
  String currentLink(String stream) => p.join(streamDir(stream), 'current');
  String previousLink(String stream) => p.join(streamDir(stream), 'previous');

  /// The version `current` resolves to, or null when the stream was never
  /// installed. Read as the link's own target, never by walking the directory.
  String? currentVersion(String stream) {
    final link = io.Link(currentLink(stream));
    if (!link.existsSync()) return null;
    return p.basename(link.targetSync());
  }

  String? previousVersion(String stream) {
    final link = io.Link(previousLink(stream));
    if (!link.existsSync()) return null;
    return p.basename(link.targetSync());
  }

  /// The executables held by a materialized version.
  List<String> namesIn(String stream, String version) {
    final dir = io.Directory(p.join(versionDir(stream, version), 'bin'));
    if (!dir.existsSync()) return const [];
    return [
      for (final entry in dir.listSync())
        if (entry is io.File) p.basename(entry.path),
    ]..sort();
  }

  /// True when this exact artifact is already materialized — same version,
  /// same hash. Re-installing is then a link swap and no download, which is
  /// what makes `update` cheap when only one binary moved.
  bool holds(String stream, String version, String name, String expectedSha256) {
    final file = io.File(p.join(versionDir(stream, version), 'bin', name));
    if (!file.existsSync()) return false;
    return sha256.convert(file.readAsBytesSync()).toString() ==
        expectedSha256.toLowerCase();
  }

  /// Open a version for writing, seeded with everything the current version
  /// already holds. Carrying forward is what keeps a surgical
  /// `bentos install mem` from leaving the other names unlinked: `current`
  /// always resolves to a complete set.
  String openVersion(String stream, String version) {
    final target = p.join(versionDir(stream, version), 'bin');
    io.Directory(target).createSync(recursive: true);
    final live = currentVersion(stream);
    if (live != null && live != version) {
      for (final name in namesIn(stream, live)) {
        final destination = io.File(p.join(target, name));
        if (destination.existsSync()) continue;
        final source = io.File(p.join(versionDir(stream, live), 'bin', name));
        destination.writeAsBytesSync(source.readAsBytesSync(), flush: true);
        _makeExecutable(destination.path);
      }
    }
    return target;
  }

  /// Verify, then materialize. The hash is checked *before* the file exists
  /// under its own name, so a corrupt download never becomes an installed
  /// binary even for the instant between write and check.
  void materialize({
    required String stream,
    required String version,
    required String name,
    required Uint8List bytes,
    required String expectedSha256,
  }) {
    final actual = sha256.convert(bytes).toString();
    if (actual != expectedSha256.toLowerCase()) {
      throw IntegrityException(
        '$name: sha256 mismatch — manifest says $expectedSha256, download is $actual',
      );
    }
    final dir = openVersion(stream, version);
    final staged = io.File(p.join(dir, '.$name.incoming'));
    staged.writeAsBytesSync(bytes, flush: true);
    _makeExecutable(staged.path);
    staged.renameSync(p.join(dir, name));
  }

  /// Point `current` at [version], remembering what it pointed at before.
  /// The swap is a rename over a staged link, which is atomic on every
  /// filesystem we run on — there is no window in which `current` is absent.
  void activate(String stream, String version) {
    final live = currentVersion(stream);
    if (live != null && live != version) {
      _swapLink(previousLink(stream), live);
    }
    _swapLink(currentLink(stream), version);
  }

  /// Trade `current` and `previous`. Returns the version now live, or null
  /// when the stream has no earlier version to go back to.
  String? rollback(String stream) {
    final live = currentVersion(stream);
    final back = previousVersion(stream);
    if (back == null) return null;
    _swapLink(currentLink(stream), back);
    if (live != null) _swapLink(previousLink(stream), live);
    return back;
  }

  /// Put [names] on the PATH, each pointing through `current` so that the next
  /// activation moves them all without touching the prefix again.
  void link(String stream, Iterable<String> names) {
    io.Directory(prefix).createSync(recursive: true);
    for (final name in names) {
      final target = p.join(currentLink(stream), 'bin', name);
      final path = p.join(prefix, name);
      final staged = p.join(prefix, '.$name.incoming');
      _removeAnything(staged);
      io.Link(staged).createSync(target);
      io.Link(staged).renameSync(path);
    }
  }

  /// True when [name] on the PATH is ours — a link into this store — rather
  /// than a binary somebody else put there. Nothing is replaced without it.
  bool ownsPathEntry(String name) {
    final path = p.join(prefix, name);
    final type = io.FileSystemEntity.typeSync(path, followLinks: false);
    if (type != io.FileSystemEntityType.link) return false;
    return p.isWithin(home, p.normalize(p.absolute(io.Link(path).targetSync())));
  }

  void _swapLink(String path, String target) {
    final staged = '$path.incoming';
    _removeAnything(staged);
    io.Link(staged).createSync(target);
    io.Link(staged).renameSync(path);
  }

  void _removeAnything(String path) {
    if (io.FileSystemEntity.typeSync(path, followLinks: false) !=
        io.FileSystemEntityType.notFound) {
      io.Link(path).deleteSync();
    }
  }

  void _makeExecutable(String path) {
    if (io.Platform.isWindows) return;
    io.Process.runSync('chmod', ['+x', path]);
  }
}

final class IntegrityException implements Exception {
  IntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}
