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

  /// Whether [placeRoot] carries the residence marker. The probe is a
  /// filesystem stat, and a whole-machine scan meets directories it cannot
  /// read — a permission-denied (or otherwise unreadable) probe is simply
  /// "not a place", never fatal. Every marker test in the organ flows through
  /// here so the resilience lives in one place.
  static bool isMarked(Directory placeRoot, FileSystem fs) {
    try {
      return markerDir(placeRoot, fs).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  /// The `.place/place.yaml` metadata file.
  static File metaFile(Directory placeRoot, FileSystem fs) =>
      fs.file(fs.path.join(placeRoot.path, dirName, 'place.yaml'));

  /// The base of every inhabitant's memory store: `<place>/.place/mem/`.
  static Directory memBase(Directory placeRoot, FileSystem fs) =>
      fs.directory(fs.path.join(placeRoot.path, dirName, 'mem'));

  /// The base of every inhabitant's execution state: `<place>/.place/tx/`.
  static Directory txBase(Directory placeRoot, FileSystem fs) =>
      fs.directory(fs.path.join(placeRoot.path, dirName, 'tx'));

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
