import 'dart:io';

/// Reads a page body from `--file` when given, else from stdin. Stdin arrives
/// as a *reader* rather than as text, so it is consumed only when the body is
/// actually wanted — a verb that needs no body never touches the stream, and
/// an inherited pipe that never closes can therefore never hang a read verb.
/// `remember` requires a body: an empty or absent one is an error here, never
/// a silent metadata-only patch — the quiet-partial a memory organ must not
/// have.
final class BodySource {
  const BodySource({this.stdinReader});

  /// Drains stdin when called; null = no stdin available.
  final Future<String> Function()? stdinReader;

  /// The body for a write. [filePath] wins over stdin and short-circuits the
  /// reader entirely. Throws [BodyMissing] when the resolved body is empty or
  /// absent, [FileSystemException] when [filePath] points nowhere.
  Future<String> read({String? filePath}) async {
    final raw = filePath != null
        ? _fromFile(filePath)
        : (stdinReader == null ? '' : await stdinReader!());
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
