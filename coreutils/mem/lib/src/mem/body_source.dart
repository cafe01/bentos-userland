import 'package:file/file.dart';

/// Reads a page body from stdin or --file.
///
/// FileSystem is injected for hermetic tests.
final class BodySource {
  const BodySource(this.fileSystem);

  final FileSystem fileSystem;

  /// Read from [filePath] when given; fall back to [stdin] otherwise.
  Future<String> read({String? filePath, StringSink? stdinSink}) {
    throw UnimplementedError('BodySource.read not yet implemented');
  }
}
