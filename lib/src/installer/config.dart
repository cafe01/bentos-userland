import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

/// Where `bentos` keeps its state and which streams it watches.
///
/// The defaults are compiled in, so a machine that has nothing but the binary
/// already knows where the userland is; `~/.bentos/config.toml` overrides the
/// streams.
///
/// **The prefix is not a choice.** The names on the PATH are the binaries
/// themselves, so the directory holding them is the installer's own —
/// `~/.bentos/bin`, inside the home it stages into, which is what keeps every
/// rename on one filesystem. `BENTOS_PREFIX` exists so a gate can drive the
/// installer under its own root and is not an installation option.
final class BentosConfig {
  const BentosConfig({
    required this.home,
    required this.prefix,
    required this.legacyPrefix,
    required this.streams,
  });

  /// `~/.bentos` — versions, state, staging, the config itself.
  final String home;

  /// `<home>/bin` — where the installed executables live, and the one directory
  /// this product asks to be on the PATH.
  final String prefix;

  /// Where the layout before substitution put the names — `~/.local/bin`, the
  /// old bootstrap's default. Not a prefix we install into: the one directory
  /// we look at to leave a machine that predates this store still working.
  /// `BENTOS_LEGACY_PREFIX` exists so a gate can mount a fixture of that layout
  /// under its own root.
  final String legacyPrefix;

  final Map<String, StreamConfig> streams;

  /// The compiled-in default, so a machine holding nothing but this binary
  /// already knows where the userland is.
  ///
  /// One repo is one product, so the producing repo is the userland's own and
  /// the tag needs no prefix to say which product it belongs to.
  static const defaultStreams = <String, StreamConfig>{
    'bentos-userland': StreamConfig(
      name: 'bentos-userland',
      repo: 'cafe01/bentos-userland',
      tagPrefix: 'v',
    ),
  };

  String get versionsDir => p.join(home, 'versions');
  String get configPath => p.join(home, 'config.toml');

  StreamConfig? stream(String name) => streams[name];

  /// The config as the process sees it: compiled-in defaults, then the file,
  /// then `BENTOS_HOME` / `BENTOS_PREFIX`. [environment] and [homeDir] are
  /// injected so a test never reads the operator's own machine.
  static BentosConfig load({
    Map<String, String>? environment,
    String? homeDir,
  }) {
    final env = environment ?? io.Platform.environment;
    final userHome = homeDir ?? env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final home = env['BENTOS_HOME'] ?? p.join(userHome, '.bentos');

    final streams = <String, StreamConfig>{...defaultStreams};

    final file = io.File(p.join(home, 'config.toml'));
    if (file.existsSync()) {
      final doc = TomlDocument.parse(file.readAsStringSync()).toMap();
      final declared = doc['streams'];
      if (declared is Map) {
        for (final entry in declared.entries) {
          final body = entry.value;
          if (body is! Map) continue;
          streams['${entry.key}'] = StreamConfig(
            name: '${entry.key}',
            repo: body['repo'] as String?,
            tagPrefix: body['tag_prefix'] as String?,
            dir: switch (body['dir']) {
              final String d when d.isNotEmpty => _expandUser(d, userHome),
              _ => null,
            },
          );
        }
      }
    }

    final envPrefix = env['BENTOS_PREFIX'];
    final prefix = envPrefix != null && envPrefix.isNotEmpty
        ? _expandUser(envPrefix, userHome)
        : p.join(home, 'bin');

    final envLegacy = env['BENTOS_LEGACY_PREFIX'];
    final legacyPrefix = envLegacy != null && envLegacy.isNotEmpty
        ? _expandUser(envLegacy, userHome)
        : p.join(userHome, '.local', 'bin');

    return BentosConfig(
      home: home,
      prefix: prefix,
      legacyPrefix: legacyPrefix,
      streams: streams,
    );
  }

  static String _expandUser(String path, String userHome) =>
      path.startsWith('~/') ? p.join(userHome, path.substring(2)) : path;
}

/// One producing repo. A stream is either a GitHub repo (the real registry) or
/// a local directory holding a manifest and its assets — the fixture form,
/// which proves the mechanism without a network.
final class StreamConfig {
  const StreamConfig({required this.name, this.repo, this.tagPrefix, this.dir});

  final String name;
  final String? repo;

  /// Which product's releases in [repo] this stream means.
  final String? tagPrefix;
  final String? dir;

  bool get isLocal => dir != null;
}
