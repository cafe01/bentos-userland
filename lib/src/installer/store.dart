import 'dart:io' as io;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'state.dart';

/// Rename one path onto another. The seam exists so a gate can make the rename
/// fail the way a cross-device rename fails and watch the failure come out —
/// the mechanism this store is built on is that a rename either happens whole
/// or does not happen, and a fallback that copies instead would keep the store
/// working while destroying that guarantee.
typedef FileRenamer = void Function(String from, String to);

void renameOnDisk(String from, String to) => io.File(from).renameSync(to);

/// One executable on the PATH, judged against the version that is supposed to
/// be live.
final class DriftEntry {
  const DriftEntry({required this.name, required this.state});

  final String name;
  final DriftState state;

  bool get isDrift => state != DriftState.installed;
}

enum DriftState {
  /// The file on the PATH is byte-for-byte the artifact of the live version.
  installed,

  /// The live version holds this name and the PATH does not.
  missing,

  /// Something else is on the PATH under our name.
  drifted,
}

/// The on-disk half of the installer: where versions land, and the rename that
/// puts one of them on the PATH.
///
/// ```
/// <home>/versions/<stream>/<version>/bin/<name>   the artifacts, immutable
/// <home>/state.json                               which version is live
/// <home>/staging/                                 where a file waits to be renamed
/// <home>/bin/<name>                               the PATH entry — the binary itself
/// ```
///
/// **Activation is substitution.** The name on the PATH is a real executable,
/// and moving to another version rewrites each of those files by renaming a
/// staged copy over it. Nothing resolves through an indirection, so nothing on
/// the PATH can be left pointing at a version that is being replaced.
///
/// The staging area is inside [home] on purpose: `rename(2)` across filesystems
/// does not degrade to a copy, it fails with `EXDEV`, and a staging area under
/// the machine's temp directory is a different filesystem on most hosts we run
/// on. Everything that will be renamed is written next to where it is going.
///
/// What this store no longer buys is set atomicity — ten names move in ten
/// renames, and an interrupted activation leaves some moved and some not. There
/// is no consumer of the stronger guarantee: what a caller needs is that each
/// binary is whole, which rename gives, and that an interrupted activation can
/// be run again, which it can, because the artifacts are immutable and the
/// pointer is written last.
final class VersionStore {
  VersionStore({
    required this.home,
    required this.prefix,
    FileRenamer? rename,
    bool? windowsSemantics,
  })  : _rename = rename ?? renameOnDisk,
        _windows = windowsSemantics ?? io.Platform.isWindows;

  final String home;
  final String prefix;
  final FileRenamer _rename;

  /// Whether the host refuses to rename over a file that is being executed.
  /// Injected rather than read, so the path that exists for Windows is driven
  /// by a gate on every host instead of only where it cannot be run.
  final bool _windows;

  String streamDir(String stream) => p.join(home, 'versions', stream);
  String versionDir(String stream, String version) => p.join(streamDir(stream), version);

  /// A manifest name as it must sit on the PATH. Platform-agnostic everywhere
  /// but here: the manifest, the version store's own artifact directories and
  /// the downloaded bytes all speak the bare name — this is the one seam where
  /// Windows needs `.exe` to be found by that name at all, since shell name
  /// resolution there goes through `PATHEXT` and a file with no recognized
  /// extension is invisible to a bare invocation.
  String _prefixName(String name) => _windows ? '$name.exe' : name;

  /// Where a file waits to be renamed into place. Inside [home] by construction:
  /// see the note on cross-device renames above.
  String get stagingDir => p.join(home, 'staging');

  InstallState get state => InstallState.read(home);

  String? currentVersion(String stream) => state[stream]?.current;
  String? previousVersion(String stream) => state[stream]?.previous;

  /// Where a materialized version keeps one name — the bytes any claim about
  /// what is installed is judged against.
  String artifactPath(String stream, String version, String name) =>
      p.join(versionDir(stream, version), 'bin', name);

  /// The executables held by a materialized version.
  List<String> namesIn(String stream, String version) {
    final dir = io.Directory(p.join(versionDir(stream, version), 'bin'));
    if (!dir.existsSync()) return const [];
    return [
      for (final entry in dir.listSync())
        if (entry is io.File) p.basename(entry.path),
    ]..sort();
  }

  /// Which of [names] the prefix already holds a file for. Read before an
  /// activation, it is what tells a first install from a replacement — the two
  /// write the same bytes and only one of them displaces something the caller
  /// may already be running.
  Set<String> namesInPrefix(Iterable<String> names) => {
        for (final name in names)
          if (io.FileSystemEntity.typeSync(p.join(prefix, _prefixName(name)), followLinks: false) !=
              io.FileSystemEntityType.notFound)
            name,
      };

  /// True when this exact artifact is already materialized — same version,
  /// same hash. Re-installing is then a rename and no download.
  bool holds(String stream, String version, String name, String expectedSha256) {
    final file = io.File(p.join(versionDir(stream, version), 'bin', name));
    if (!file.existsSync()) return false;
    return sha256.convert(file.readAsBytesSync()).toString() ==
        expectedSha256.toLowerCase();
  }

  /// Open a version for writing, seeded with everything the live version
  /// already holds. Carrying forward is what keeps a surgical
  /// `bentos install mem` from leaving the other names behind: the version that
  /// gets activated always holds a complete set.
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
    _rename(staged.path, p.join(dir, name));
  }

  /// Put [version] on the PATH, at exactly the [names] given — every other
  /// name it holds stays whatever the prefix already has. Returns the names
  /// whose bytes in the prefix actually changed — which is the only reading
  /// any report about this machine may be built from.
  ///
  /// [names] defaults to everything the version holds, which is what a whole
  /// install or an update means; a scoped call — `self-update` asking for
  /// just [names] `{bentos}` — is how the store keeps its promise that only
  /// the requested name moves. `openVersion` carries every other name forward
  /// unchanged into the new version's directory, so leaving one out of this
  /// loop leaves it out of the prefix too.
  ///
  /// The pointer going last is what makes an interrupted activation safe to
  /// repeat — a run that dies halfway leaves `state.json` still naming the old
  /// version, and running the same command again finishes the substitution.
  Set<String> activate(String stream, String version, {Iterable<String>? names}) {
    final changed = <String>{};
    for (final name in names ?? namesIn(stream, version)) {
      if (substitute(stream: stream, version: version, name: name)) {
        changed.add(name);
      }
    }
    InstallState.read(home).activate(stream, version);
    return changed;
  }

  /// Return a stream to its previous version, substituting the binaries back.
  /// Nothing is fetched: the artifacts of the earlier version were never
  /// deleted. Returns what it did — the version now live, the one it came from,
  /// and the names whose bytes in the prefix actually changed — or null when
  /// there is no previous version.
  ///
  /// The changed names come back for the same reason [activate]'s do: a report
  /// about this machine may be built from nothing else.
  RollbackOutcome? rollback(String stream) {
    final from = currentVersion(stream);
    final back = previousVersion(stream);
    if (back == null) return null;
    final changed = <String>{};
    for (final name in namesIn(stream, back)) {
      if (substitute(stream: stream, version: back, name: name)) {
        changed.add(name);
      }
    }
    InstallState.read(home).rollback(stream);
    return RollbackOutcome(version: back, from: from, changed: changed);
  }

  /// Write one artifact over its name in the prefix. Returns whether the bytes
  /// at the destination changed — false when the prefix already held exactly
  /// this artifact, in which case nothing is written at all.
  ///
  /// The answer is read from the destination's own bytes and never from what
  /// the version store holds, because the two are exactly what drift makes
  /// disagree: a report built from the store would call a cured machine
  /// untouched.
  ///
  /// The bytes are staged inside [home] and renamed into place, so the file at
  /// the destination is either the whole old binary or the whole new one and
  /// never a half-written thing that a shell could pick up between the two.
  bool substitute({
    required String stream,
    required String version,
    required String name,
  }) {
    final source = io.File(p.join(versionDir(stream, version), 'bin', name));
    if (!source.existsSync()) {
      throw IntegrityException(
        '$name: version $version of "$stream" does not hold it',
      );
    }
    if (_prefixHolds(name, source)) return false;
    io.Directory(stagingDir).createSync(recursive: true);
    io.Directory(prefix).createSync(recursive: true);

    final staged = io.File(p.join(stagingDir, '$name.incoming'));
    if (staged.existsSync()) staged.deleteSync();
    staged.writeAsBytesSync(source.readAsBytesSync(), flush: true);
    _makeExecutable(staged.path);

    final destination = p.join(prefix, _prefixName(name));
    _displaceRunningExecutable(destination);
    _rename(staged.path, destination);
    return true;
  }

  /// Whether the name in the prefix is already, byte for byte, [source].
  bool _prefixHolds(String name, io.File source) {
    final destination = io.File(p.join(prefix, _prefixName(name)));
    if (io.FileSystemEntity.typeSync(destination.path, followLinks: false) !=
        io.FileSystemEntityType.file) {
      return false;
    }
    return sha256.convert(destination.readAsBytesSync()) ==
        sha256.convert(source.readAsBytesSync());
  }

  /// A host that refuses to rename over a running executable is given the file
  /// out of the way first — which is how `bentos` replaces the very binary the
  /// caller is inside of. On POSIX nothing is displaced: the rename unlinks the
  /// old inode and the running process keeps executing it.
  ///
  /// Unproven on Windows itself: no gate has ever run there, and the slice that
  /// makes Windows install owns that proof.
  void _displaceRunningExecutable(String destination) {
    if (!_windows) return;
    if (io.FileSystemEntity.typeSync(destination) == io.FileSystemEntityType.notFound) {
      return;
    }
    final displaced = io.File('$destination.old');
    if (displaced.existsSync()) {
      // A previous replacement's leftover, still locked if that process lives.
      try {
        displaced.deleteSync();
      } on io.FileSystemException {
        return;
      }
    }
    _rename(destination, displaced.path);
  }

  /// What the PATH actually holds against what the live version says it should:
  /// every name of the live version, hashed on both sides.
  ///
  /// The comparison is against the materialized artifact and not against the
  /// manifest, which is the same claim read offline — nothing reaches
  /// `<home>/versions` without having been checked against the manifest's hash
  /// at [materialize].
  List<DriftEntry> drift(String stream) {
    final version = currentVersion(stream);
    if (version == null) return const [];
    return [
      for (final name in namesIn(stream, version))
        DriftEntry(name: name, state: _driftOf(stream, version, name)),
    ];
  }

  DriftState _driftOf(String stream, String version, String name) {
    // The prefix's own file, which is not necessarily what the PATH answers:
    // whether anyone reaches it is the shadow reading's question, and saying
    // "on the PATH" here is how this check came to describe a machine it had
    // not looked at.
    final inPrefix = io.File(p.join(prefix, _prefixName(name)));
    if (io.FileSystemEntity.typeSync(inPrefix.path, followLinks: false) ==
        io.FileSystemEntityType.notFound) {
      return DriftState.missing;
    }
    final held = io.File(p.join(versionDir(stream, version), 'bin', name));
    if (!held.existsSync()) return DriftState.drifted;
    final installed = sha256.convert(inPrefix.readAsBytesSync()).toString();
    final expected = sha256.convert(held.readAsBytesSync()).toString();
    return installed == expected ? DriftState.installed : DriftState.drifted;
  }

  void _makeExecutable(String path) {
    if (io.Platform.isWindows) return;
    io.Process.runSync('chmod', ['+x', path]);
  }
}

/// What a rollback did to the prefix.
final class RollbackOutcome {
  const RollbackOutcome({
    required this.version,
    required this.from,
    required this.changed,
  });

  /// The version now live.
  final String version;

  /// The version it was rolled back from.
  final String? from;

  /// The names whose bytes in the prefix changed.
  final Set<String> changed;
}

final class IntegrityException implements Exception {
  IntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}
