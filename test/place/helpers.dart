import 'package:file/file.dart';
import 'package:file/memory.dart';

/// A hermetic place habitat: a MemoryFileSystem with an injected home, plus
/// helpers to mark places and seed metadata.
final class Habitat {
  Habitat({this.home = '/home/john'}) {
    fs.directory(home).createSync(recursive: true);
  }

  final FileSystem fs = MemoryFileSystem();
  final String home;

  /// Mark [dirPath] as a place (create `.place/`), optionally with metadata.
  Directory place(String dirPath, {String? yaml}) {
    final dir = fs.directory(dirPath)..createSync(recursive: true);
    fs.directory(fs.path.join(dirPath, '.place')).createSync(recursive: true);
    if (yaml != null) {
      fs.file(fs.path.join(dirPath, '.place', 'place.yaml')).writeAsStringSync(yaml);
    }
    return dir;
  }

  /// Create a plain directory (no marker).
  Directory dir(String dirPath) =>
      fs.directory(dirPath)..createSync(recursive: true);
}
