import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'commands/info_command.dart';
import 'commands/init_command.dart';
import 'commands/superrepo_commands.dart';
import 'commands/tree_command.dart';
import 'commands/where_command.dart';
import 'commands/who_command.dart';
import 'habitat_index.dart';
import 'home_ambient.dart';
import 'place.dart';

/// The `place` coreutil's command runner: the five spatial verbs (`where`,
/// `tree`, `info`, `who`, `init`) and the superrepo's (`ls`, `pin`,
/// `timeline`), all reading through the Place API.
/// The current directory is injected for hermetic testing; the filesystem
/// itself rides `Place`'s own `IOOverrides`/zone hermeticity.
final class PlaceRunner {
  PlaceRunner({
    StringSink? out,
    StringSink? err,
    String? currentDirectory,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        _cwdOverride = currentDirectory {
    _runner = CommandRunner<void>(
      'place',
      'The WHERE organ — orient in space: where, tree, info, who, init; and the constellation: ls, pin, timeline.',
    )
      ..addCommand(WhereCommand(this))
      ..addCommand(TreeCommand(this))
      ..addCommand(InfoCommand(this))
      ..addCommand(WhoCommand(this))
      ..addCommand(InitCommand(this))
      ..addCommand(LsCommand(this))
      ..addCommand(PinCommand(this))
      ..addCommand(TimelineCommand(this));
  }

  final StringSink out;
  final StringSink err;
  final String? _cwdOverride;

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  /// The current working directory — injected override, else the process cwd.
  String get cwd => _cwdOverride ?? io.Directory.current.path;

  /// The located habitat index for `where`, centered on [current]: bounded to
  /// the habitat subtree, with the machine root and home grafted above as
  /// resolved context. Never a whole-machine walk (see
  /// [HabitatIndex.neighborhood]). The platform-native system roots are still
  /// passed as prune roots, harmless within the habitat and load-bearing in the
  /// implicit-root fallback.
  HabitatIndex neighborhood(Place current) =>
      HabitatIndex.neighborhood(current, pruneRoots: systemRoots);

  /// The habitat index scoped to the subtree rooted at [place] — the places
  /// nested under (and including) it, not the whole machine. `place tree`
  /// wants exactly this subtree, so scanning from `/` and discarding
  /// everything outside the node is pure waste: on a large home the
  /// whole-machine walk dominates the command. The home is not injected as an
  /// implicit terminal (it lives above the subtree, not within it).
  HabitatIndex indexUnder(Place place) => HabitatIndex.scan(
        from: place.root.path,
        pruneRoots: systemRoots,
        includeImplicitHome: false,
      );

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
        p.join(ambientHome, 'Library'), // the home's own native bulk
      };
    }
    if (io.Platform.isWindows) {
      return {
        r'C:\Windows', r'C:\Program Files', r'C:\Program Files (x86)',
        r'C:\ProgramData',
        p.join(ambientHome, 'AppData'),
      };
    }
    // Linux and other POSIX.
    return {
      '/proc', '/sys', '/dev', '/run', '/usr', '/bin', '/sbin',
      '/lib', '/lib32', '/lib64', '/libx32', '/boot', '/opt', '/snap',
    };
  }

  /// The place enclosing [pathArg], defaulting to the current directory.
  /// Relative paths resolve against the injected [cwd], not the process's own.
  Place placeAt(String? pathArg) {
    final target = pathArg ?? cwd;
    final abs = p.isAbsolute(target) ? target : p.join(cwd, target);
    return Place(p.normalize(abs));
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
