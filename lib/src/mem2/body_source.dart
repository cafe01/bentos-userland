import 'dart:io';

/// Reads a page body from `--file` when given, else from stdin. The stdin text
/// is injected so the read is hermetic; file reads ride `IOOverrides`.
/// `remember` requires a body: an empty or absent one is an error here, never
/// a silent metadata-only patch — the quiet-partial a memory organ must not
/// have.
final class BodySource {
  const BodySource({this.stdinContent});

  /// Pre-canned stdin for tests; null = no stdin available.
  final String? stdinContent;

  /// The body for a write. [filePath] wins over stdin. Throws [BodyMissing]
  /// when the resolved body is empty or absent, [FileSystemException] when
  /// [filePath] points nowhere.
  String read({String? filePath}) {
    final raw = filePath != null ? _fromFile(filePath) : (stdinContent ?? '');
    if (raw.trim().isEmpty) throw const BodyMissing();
    return raw.trim();
  }

  String _fromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('body file not found', path);
    }
    return file.readAsStringSync();
  }
}

/// Raised when `remember` is given no body — the write refuses rather than
/// silently keeping the old body.
final class BodyMissing implements Exception {
  const BodyMissing();

  @override
  String toString() => 'remember: no body — pipe one on stdin or pass --file PATH.';
}
