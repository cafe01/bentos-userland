import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'store.dart';

/// What one stream's adoption moved.
final class AdoptionReport {
  const AdoptionReport({
    required this.stream,
    required this.version,
    required this.previous,
    required this.substituted,
    required this.shimmed,
  });

  final String stream;
  final String version;
  final String? previous;

  /// Names written into the new prefix as real binaries.
  final List<String> substituted;

  /// Names in the old prefix that now forward to the new one.
  final List<String> shimmed;
}

/// The machine that was installed by the version before substitution, brought
/// into the store this binary understands.
///
/// The old layout put symlinks on the PATH pointing *through*
/// `<home>/versions/<stream>/current`, and carried the pointer as those links.
/// The new store has no reading for any of it — so a machine holding the old
/// layout is not one this binary breaks, it is one this binary *ignores*: it
/// builds a correct world in `<home>/bin`, which is not on that machine's PATH,
/// while the names the person actually runs keep resolving through `current`
/// and stay frozen at whatever version was live when the old code last ran.
/// Every update after that reports success and changes nothing they execute.
///
/// A dangling link announces itself. This does not, which is why adoption runs
/// on its own at the top of every verb that reads or writes the store rather
/// than waiting behind a command someone has to know to type.
///
/// **The old prefix is left working, never cleaned.** It stopped being ours,
/// and a person's PATH names it: each entry that is provably ours becomes a
/// link forward to the real binary, so the machine keeps working through the
/// same names it always did. That link is compatibility in a directory we no
/// longer own — activation itself resolves through nothing. What is *not*
/// provably ours is not touched at all: replacing a file we cannot prove we put
/// there is spending someone else's machine on an inference.
final class LegacyLayout {
  const LegacyLayout({
    required this.home,
    required this.legacyPrefix,
    required this.store,
  });

  final String home;

  /// Where the old bootstrap put the names — `~/.local/bin` by default.
  final String legacyPrefix;

  final VersionStore store;

  String currentLink(String stream) => p.join(store.streamDir(stream), 'current');
  String previousLink(String stream) => p.join(store.streamDir(stream), 'previous');

  /// The old layout's one unambiguous marker: `current` exists and is a link.
  /// The new store never writes it, so its presence dates the machine.
  bool holdsStream(String stream) => _linkTarget(currentLink(stream)) != null;

  /// Adopt every stream still carrying the old layout. A machine that has none
  /// — including a machine that has nothing at all — returns an empty list
  /// having read two paths and written nothing.
  List<AdoptionReport> adopt(Iterable<String> streams) => [
        for (final stream in streams)
          if (holdsStream(stream)) _adoptStream(stream),
      ];

  AdoptionReport _adoptStream(String stream) {
    final version = p.basename(_linkTarget(currentLink(stream))!);
    final previous = switch (_linkTarget(previousLink(stream))) {
      final String target => p.basename(target),
      _ => null,
    };

    // The binaries first. The shim is written only once what it forwards to
    // exists, so no order of interruption leaves a name pointing at nothing.
    final substituted = store.namesIn(stream, version);
    for (final name in substituted) {
      store.substitute(stream: stream, version: version, name: name);
    }

    // Both ends of the old pointer are adopted: `previous` is one link read and
    // it is the whole of what rollback needs, so a machine that could go back
    // before adoption can still go back after it.
    store.state.adopt(stream, current: version, previous: previous);

    final shimmed = _shimOldPrefix();

    // The pointer of the dead mechanism, last: while these links stand, the old
    // layout is still detectable and the adoption is still repeatable.
    _unlink(currentLink(stream));
    _unlink(previousLink(stream));

    return AdoptionReport(
      stream: stream,
      version: version,
      previous: previous,
      substituted: substituted,
      shimmed: shimmed,
    );
  }

  /// Every entry of the old prefix that is provably ours — a symlink whose
  /// target lies inside our home — is pointed at the real binary instead.
  /// Anything else in that directory is somebody's, and untouched.
  List<String> _shimOldPrefix() {
    final dir = io.Directory(legacyPrefix);
    if (!dir.existsSync()) return const [];
    final shimmed = <String>[];
    for (final entry in dir.listSync(followLinks: false)) {
      final name = p.basename(entry.path);
      final target = _linkTarget(entry.path);
      final isOursByLink =
          target != null && p.isWithin(home, p.normalize(p.absolute(target)));
      if (!isOursByLink) continue;
      final destination = p.join(store.prefix, store.prefixName(name));
      if (!io.File(destination).existsSync()) continue;
      final staged = p.join(legacyPrefix, '.$name.incoming');
      _unlink(staged);
      io.Link(staged).createSync(destination);
      io.Link(staged).renameSync(entry.path);
      shimmed.add(name);
    }
    return shimmed..sort();
  }

  static String? _linkTarget(String path) {
    if (io.FileSystemEntity.typeSync(path, followLinks: false) !=
        io.FileSystemEntityType.link) {
      return null;
    }
    return io.Link(path).targetSync();
  }

  static void _unlink(String path) {
    if (io.FileSystemEntity.typeSync(path, followLinks: false) !=
        io.FileSystemEntityType.notFound) {
      io.Link(path).deleteSync();
    }
  }
}

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
  const PathShadows({
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
