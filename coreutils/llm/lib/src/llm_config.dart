/// Persistent configuration for the `llm` coreutil.
///
/// Holds two optional fields — the default device and a name→path alias map.
/// ZERO keys: credentials belong to the driver.
///
/// Stored as JSON at `$XDG_CONFIG_HOME/humanos/llm/config.json`
/// (falling back to `~/.config/humanos/llm/config.json`).
library;

import 'dart:convert';
import 'dart:io';

class LlmConfig {
  String? defaultDevice;
  final Map<String, String> aliases;

  LlmConfig({this.defaultDevice, Map<String, String>? aliases})
      : aliases = aliases ?? {};

  /// The default config file path, respecting `$XDG_CONFIG_HOME`.
  static File get configFile {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'] ?? '.';
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.config';
    return File('$base/humanos/llm/config.json');
  }

  /// Loads config from [file] (defaults to [configFile]). Returns an empty
  /// config when the file does not exist — `llm` works out of the box.
  static LlmConfig load({File? file}) {
    final f = file ?? configFile;
    if (!f.existsSync()) return LlmConfig();
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return LlmConfig(
      defaultDevice: json['default'] as String?,
      aliases: (json['aliases'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
    );
  }

  /// Persists this config to [file] (defaults to [configFile]).
  void save({File? file}) {
    final f = file ?? configFile;
    f.parent.createSync(recursive: true);
    final data = <String, dynamic>{
      if (defaultDevice != null) 'default': defaultDevice,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }
}
