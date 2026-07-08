import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'commands/info_command.dart';
import 'commands/init_command.dart';
import 'commands/tree_command.dart';
import 'commands/where_command.dart';
import 'commands/who_command.dart';
import 'habitat_index.dart';
import 'model/place.dart';
import 'place_resolver.dart';

/// The `place` coreutil's command runner: dispatch to the five spatial verbs
/// (`where`, `tree`, `info`, `who`, `init`), all reading through the Place API.
/// Every dependency — filesystem, home, cwd, streams — is injected here so the
/// whole organ is hermetically testable.
final class PlaceRunner {
  PlaceRunner({
    StringSink? out,
    StringSink? err,
    FileSystem? fileSystem,
    String? home,
    String? currentDirectory,
    Map<String, String>? environment,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        fs = fileSystem ?? const LocalFileSystem(),
        _homeOverride = home,
        _cwdOverride = currentDirectory,
        _environment = environment ?? io.Platform.environment {
    _runner = CommandRunner<void>(
      'place',
      'The WHERE organ — orient in space: where, tree, info, who, init.',
    )
      ..addCommand(WhereCommand(this))
      ..addCommand(TreeCommand(this))
      ..addCommand(InfoCommand(this))
      ..addCommand(WhoCommand(this))
      ..addCommand(InitCommand(this));
  }

  final StringSink out;
  final StringSink err;
  final FileSystem fs;
  final String? _homeOverride;
  final String? _cwdOverride;
  final Map<String, String> _environment;

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  /// The current working directory — injected override, else the fs's cwd.
  String get cwd => _cwdOverride ?? fs.currentDirectory.path;

  String get home =>
      _homeOverride ?? _environment['HOME'] ?? fs.currentDirectory.path;

  PlaceResolver get resolver => PlaceResolver(fs: fs, home: home);

  /// The habitat index, scanned once from the machine root, with the
  /// platform-native system roots pruned so the walk stays in user space.
  HabitatIndex index() => HabitatIndex.scan(resolver, pruneRoots: systemRoots);

  /// The OS-native system directories, which hold no places and otherwise
  /// dominate a whole-machine walk. Pruned by absolute path, so a non-system
  /// place at a direct child of `/` is still discovered. Platform-selected
  /// here (the one spot that reads `dart:io`); `/` itself is never pruned.
  Set<String> get systemRoots {
    // Only NON-hidden system dirs need listing here — hidden ones (`.Trash`,
    // `.cache`, `.pub-cache`, …) are already pruned wholesale by the descent.
    if (io.Platform.isMacOS) {
      return {
        '/System', '/Library', '/private', '/usr', '/bin', '/sbin',
        '/cores', '/dev', '/opt', '/Applications', '/Volumes',
        fs.path.join(home, 'Library'), // the home's own native bulk
      };
    }
    if (io.Platform.isWindows) {
      return {
        r'C:\Windows', r'C:\Program Files', r'C:\Program Files (x86)',
        r'C:\ProgramData',
        fs.path.join(home, 'AppData'),
      };
    }
    // Linux and other POSIX.
    return {
      '/proc', '/sys', '/dev', '/run', '/usr', '/bin', '/sbin',
      '/lib', '/lib32', '/lib64', '/libx32', '/boot', '/opt', '/snap',
    };
  }

  /// The place enclosing [pathArg], defaulting to the current directory.
  /// Relative paths resolve against the injected [cwd], not the fs's own.
  Place placeAt(String? pathArg) {
    final p = pathArg ?? cwd;
    final abs = fs.path.isAbsolute(p) ? p : fs.path.join(cwd, p);
    return resolver.enclosing(fs.path.normalize(abs));
  }

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = 64;
    }
  }
}
