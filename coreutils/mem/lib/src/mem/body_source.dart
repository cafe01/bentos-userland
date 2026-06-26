import 'dart:io' as io;

import 'package:file/file.dart';

/// Reads a page body from stdin or --file.
///
/// FileSystem is injected for hermetic tests.
final class BodySource {
  const BodySource(this.fileSystem);

  final FileSystem fileSystem;

  /// Read from [filePath] when given; fall back to real stdin otherwise.
  Future<String> read({String? filePath, StringSink? stdinSink}) async {
    if (filePath != null) {
      final file = fileSystem.file(filePath);
      if (!file.existsSync()) {
        throw ArgumentError('File not found: $filePath');
      }
      return file.readAsStringSync();
    }
    return io.stdin.transform(io.systemEncoding.decoder).join();
  }
}
