import 'dart:io' as io;

import 'package:file/file.dart';

/// Reads a page body from stdin or --file.
///
/// FileSystem is injected for hermetic tests. [stdinOverride] replaces real
/// stdin for hermetic tests.
final class BodySource {
  const BodySource(this.fileSystem, {this.stdinOverride});

  final FileSystem fileSystem;

  /// Pre-canned stdin content; null = use real stdin.
  final String? stdinOverride;

  /// Read from [filePath] when given; fall back to stdin (real or override) otherwise.
  Future<String> read({String? filePath}) async {
    if (filePath != null) {
      final file = fileSystem.file(filePath);
      if (!file.existsSync()) {
        throw ArgumentError('File not found: $filePath');
      }
      return file.readAsStringSync();
    }
    if (stdinOverride != null) return stdinOverride!;
    return io.stdin.transform(io.systemEncoding.decoder).join();
  }
}
