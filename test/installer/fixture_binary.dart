import 'dart:io';

import 'package:path/path.dart' as p;

/// A minimal native executable, one per distinct [label], compiled once and
/// cached for the life of the test process.
///
/// The old fixture was `#!/bin/sh\necho "$label"\n`, executed straight via
/// `Process.runSync`: on POSIX that runs because the shell reads the shebang,
/// and on Windows `CreateProcess` refuses it outright — the assertion "this
/// name runs as a command" never had a witness of the same matter as the
/// artifacts the installer actually ships. This compiles a real one, so the
/// only thing distinguishing labels is content a fixture is allowed to vary:
/// which literal string it was told to print.
final class FixtureBinaries {
  FixtureBinaries._();

  static final _cache = <String, List<int>>{};
  static Directory? _work;

  /// The bytes of a tiny compiled program that prints exactly [label] to
  /// stdout and exits 0.
  static List<int> bytesFor(String label) =>
      _cache.putIfAbsent(label, () => _compile(label));

  static List<int> _compile(String label) {
    final work = _work ??= Directory.systemTemp.createTempSync('bentos-fixture-src-');
    final id = _cache.length;
    final source = File(p.join(work.path, 'fixture_$id.dart'))
      ..writeAsStringSync('void main() { print(${_dartLiteral(label)}); }');
    final outPath =
        p.join(work.path, 'fixture_$id${Platform.isWindows ? '.exe' : ''}');

    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['compile', 'exe', source.path, '-o', outPath],
    );
    if (result.exitCode != 0) {
      throw StateError(
        'FixtureBinaries: compiling the "$label" witness failed:\n${result.stderr}',
      );
    }
    return File(outPath).readAsBytesSync();
  }

  static String _dartLiteral(String s) {
    final escaped = s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    return "'$escaped'";
  }
}
