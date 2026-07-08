import 'dart:io';

import 'package:file/file.dart' as f;

/// The hermetic bridge: an [IOOverrides] that delegates `dart:io` entity
/// construction and filesystem probes to a `package:file` [f.FileSystem]
/// (a `MemoryFileSystem` in tests).
///
/// package:file's entities implement the `dart:io` interfaces, so they drop
/// in directly. The bridge covers every method the place resolution walk and
/// the habitat scan touch — entity constructors, cwd, stats, type probes —
/// so a bare `Place(path)`/`File(path)`/`Directory(path)` inside the zone
/// reads and writes the injected filesystem, never the disk.
final class MemFsIOOverrides extends IOOverrides {
  MemFsIOOverrides(this.fs);

  final f.FileSystem fs;

  @override
  File createFile(String path) => fs.file(path);

  @override
  Directory createDirectory(String path) => fs.directory(path);

  @override
  Link createLink(String path) => fs.link(path);

  @override
  Directory getCurrentDirectory() => fs.currentDirectory;

  @override
  void setCurrentDirectory(String path) => fs.currentDirectory = path;

  @override
  Directory getSystemTempDirectory() => fs.systemTempDirectory;

  @override
  Future<FileStat> stat(String path) => fs.stat(path);

  @override
  FileStat statSync(String path) => fs.statSync(path);

  @override
  Future<bool> fseIdentical(String path1, String path2) =>
      fs.identical(path1, path2);

  @override
  bool fseIdenticalSync(String path1, String path2) =>
      fs.identicalSync(path1, path2);

  @override
  Future<FileSystemEntityType> fseGetType(String path, bool followLinks) =>
      fs.type(path, followLinks: followLinks);

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      fs.typeSync(path, followLinks: followLinks);
}
