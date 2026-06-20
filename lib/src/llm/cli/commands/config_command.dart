/// `llm config` — show or modify the default device and aliases.
/// No key management: credentials belong to the driver.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../config.dart';
import '../../llm_config.dart';

class ConfigCommand extends Command<int> {
  @override
  String get name => 'config';

  @override
  String get description =>
      'Show or modify the default device and aliases. '
      'No key management — credentials belong to the driver.';

  @override
  String get invocation =>
      'llm config\n'
      '  llm config default <vendor/model>\n'
      '  llm config alias <name> <vendor/model>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) return _show();

    switch (rest[0]) {
      case 'default':
        if (rest.length < 2) {
          throw UsageException(
              'usage: llm config default <vendor/model>', usage);
        }
        return _setDefault(rest[1]);

      case 'alias':
        if (rest.length < 3) {
          throw UsageException(
              'usage: llm config alias <name> <vendor/model>', usage);
        }
        return _setAlias(rest[1], rest[2]);

      default:
        throw UsageException(
            'unknown config sub-command "${rest[0]}"', usage);
    }
  }

  int _show() {
    final cfg = LlmConfig.load();
    final effective = cfg.defaultDevice ?? defaultDevicePath;
    final builtin = cfg.defaultDevice == null;
    stdout.writeln(
        'default device: $effective${builtin ? '  (built-in fallback)' : ''}');
    if (cfg.aliases.isEmpty) {
      stdout.writeln('aliases: (none)');
    } else {
      stdout.writeln('aliases:');
      final width = cfg.aliases.keys
          .map((k) => k.length)
          .reduce((a, b) => a > b ? a : b);
      for (final MapEntry(:key, :value) in cfg.aliases.entries) {
        stdout.writeln('  ${key.padRight(width)}  →  $value');
      }
    }
    return 0;
  }

  int _setDefault(String device) {
    final path = _normalize(device);
    final cfg = LlmConfig.load();
    cfg.defaultDevice = path;
    cfg.save();
    stdout.writeln('default device set to $path');
    return 0;
  }

  int _setAlias(String name, String device) {
    final path = _normalize(device);
    final cfg = LlmConfig.load();
    cfg.aliases[name] = path;
    cfg.save();
    stdout.writeln('alias "$name" → $path');
    return 0;
  }

  /// Short `vendor/model` → `/dev/llm/vendor/model`; full paths pass through.
  String _normalize(String device) =>
      device.startsWith('/') ? device : '/dev/llm/$device';
}
