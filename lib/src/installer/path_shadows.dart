import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A name that another directory on the PATH answers before ours does.
final class ShadowFinding {
  const ShadowFinding({required this.name, required this.path, required this.isOurs});

  final String name;

  /// The file that wins the PATH lookup.
  final String path;

  /// True when its bytes are the artifact we installed — a shim, or a copy of
  /// the same build. False means the person is running something else entirely.
  final bool isOurs;
}

/// What the shell will actually run, against what this installer put on disk.
///
/// The installer writes to its own prefix and cannot make anyone's PATH name it
/// first. Where an earlier directory answers the same name, every report of a
/// successful update is true and useless: the person keeps running the old
/// thing. Saying so is the whole remedy here — nothing is moved, because what
/// sits in front of us is not ours to move.
final class PathShadows {
  PathShadows({
    required this.prefix,
    required this.pathDirs,
    bool? windowsSemantics,
  }) : _windows = windowsSemantics ?? io.Platform.isWindows;

  factory PathShadows.of(
    String prefix,
    Map<String, String> environment, {
    bool? windowsSemantics,
  }) {
    final windows = windowsSemantics ?? io.Platform.isWindows;
    return PathShadows(
      prefix: prefix,
      pathDirs: (environment['PATH'] ?? '')
          .split(windows ? ';' : ':')
          .where((d) => d.isNotEmpty)
          .toList(),
      windowsSemantics: windows,
    );
  }

  final String prefix;
  final List<String> pathDirs;

  /// Same fact as [VersionStore.prefixName]: on Windows a bare name resolves
  /// through `PATHEXT`, so what actually sits ahead of us on the PATH under
  /// [name] carries `.exe`.
  final bool _windows;

  /// True when our prefix is not on the PATH at all — in which case everything
  /// on it is ahead of us.
  bool get prefixIsUnreachable => _cutoff == null;

  int? get _cutoff {
    for (var i = 0; i < pathDirs.length; i++) {
      if (p.equals(pathDirs[i], prefix)) return i;
    }
    return null;
  }

  /// The first file ahead of our prefix answering [name], or null when ours
  /// wins the lookup.
  ShadowFinding? ahead(String name, {String? ourArtifact}) {
    final fileName = _windows ? '$name.exe' : name;
    final until = _cutoff ?? pathDirs.length;
    for (var i = 0; i < until; i++) {
      final candidate = p.join(pathDirs[i], fileName);
      if (io.FileSystemEntity.typeSync(candidate) != io.FileSystemEntityType.file) {
        continue;
      }
      return ShadowFinding(
        name: name,
        path: candidate,
        isOurs: ourArtifact != null && _sameBytes(candidate, ourArtifact),
      );
    }
    return null;
  }

  static bool _sameBytes(String a, String b) {
    final left = io.File(a);
    final right = io.File(b);
    if (!left.existsSync() || !right.existsSync()) return false;
    return sha256.convert(left.readAsBytesSync()) ==
        sha256.convert(right.readAsBytesSync());
  }
}
