import 'package:file/file.dart';

/// The single component that knows the `.place/` residence layout. Every path
/// into a place's control plane is constructed here and nowhere else — the
/// seam that keeps the marker and layout swappable. Pure path law: the
/// resolvers return handles, create nothing, read nothing.
final class Residence {
  Residence._();

  /// The marker directory name. A directory is a place iff it contains this.
  static const dirName = '.place';

  /// The `.place/` control-plane directory of the place at [placeRoot].
  static Directory markerDir(Directory placeRoot, FileSystem fs) =>
      fs.directory(fs.path.join(placeRoot.path, dirName));

  /// The `.place/place.yaml` metadata file.
  static File metaFile(Directory placeRoot, FileSystem fs) =>
      fs.file(fs.path.join(placeRoot.path, dirName, 'place.yaml'));

  /// [entity]'s memory store: `<place>/.place/mem/<entity>/`.
  static Directory memoryRoot(
    Directory placeRoot,
    FileSystem fs,
    String entity,
  ) => fs.directory(fs.path.join(placeRoot.path, dirName, 'mem', entity));

  /// [entity]'s execution state for [scope]: `<place>/.place/tx/<entity>/<scope>/`.
  static Directory txRoot(
    Directory placeRoot,
    FileSystem fs,
    String entity,
    String scope,
  ) => fs.directory(fs.path.join(placeRoot.path, dirName, 'tx', entity, scope));
}
