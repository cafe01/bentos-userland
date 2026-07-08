import 'dart:async';
import 'dart:io';

import 'package:file/file.dart' as f;
import 'package:file/memory.dart';

import '../place/home_ambient.dart';
import 'mem_fs_overrides.dart';

/// Runs [body] hermetically: a fresh [MemoryFileSystem] behind the
/// [MemFsIOOverrides] bridge, plus [home] installed as the zone-scoped home
/// ambient. Inside, every call site is a bare `Place(path)`/`File(path)` —
/// no `fs` threaded anywhere; outside, the real disk and
/// `Platform.environment['HOME']` apply.
///
/// [home] is created and set as the working directory before [body] runs;
/// the filesystem is handed to [body] for seeding.
T runInMemoryFs<T>(T Function(f.FileSystem fs) body, {String home = '/home/john'}) {
  final fs = MemoryFileSystem();
  fs.directory(home).createSync(recursive: true);
  fs.currentDirectory = home;
  return runZoned(
    () => IOOverrides.runWithIOOverrides(() => body(fs), MemFsIOOverrides(fs)),
    zoneValues: {homeAmbientKey: home},
  );
}
