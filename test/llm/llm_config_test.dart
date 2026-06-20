/// Tests for LlmConfig: load/save round-trip, alias management, missing-file
/// defaults. All I/O uses an injected temp file — no real config is touched.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/llm.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('llm_config_test_');
    file = File('${tmp.path}/config.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('LlmConfig.load', () {
    test('returns empty config when file does not exist', () {
      final cfg = LlmConfig.load(file: file);
      expect(cfg.defaultDevice, isNull);
      expect(cfg.aliases, isEmpty);
    });

    test('parses defaultDevice from the "default" key', () {
      file.writeAsStringSync(
          jsonEncode({'default': '/dev/llm/anthropic/claude-sonnet-4'}));
      final cfg = LlmConfig.load(file: file);
      expect(cfg.defaultDevice, '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('parses aliases map', () {
      file.writeAsStringSync(jsonEncode({
        'aliases': {
          'sonnet': '/dev/llm/anthropic/claude-sonnet-4',
          'mini': '/dev/llm/openai/gpt-4o-mini',
        },
      }));
      final cfg = LlmConfig.load(file: file);
      expect(cfg.aliases['sonnet'], '/dev/llm/anthropic/claude-sonnet-4');
      expect(cfg.aliases['mini'], '/dev/llm/openai/gpt-4o-mini');
    });

    test('parses both default and aliases together', () {
      file.writeAsStringSync(jsonEncode({
        'default': '/dev/llm/openai/gpt-4o-mini',
        'aliases': {'fast': '/dev/llm/openai/gpt-4o-mini'},
      }));
      final cfg = LlmConfig.load(file: file);
      expect(cfg.defaultDevice, '/dev/llm/openai/gpt-4o-mini');
      expect(cfg.aliases['fast'], '/dev/llm/openai/gpt-4o-mini');
    });

    test('missing "aliases" key does not crash', () {
      file.writeAsStringSync(
          jsonEncode({'default': '/dev/llm/openai/gpt-4o-mini'}));
      final cfg = LlmConfig.load(file: file);
      expect(cfg.aliases, isEmpty);
    });

    test('missing "default" key yields null defaultDevice', () {
      file.writeAsStringSync(jsonEncode({
        'aliases': {'x': '/dev/llm/openai/gpt-4o-mini'},
      }));
      final cfg = LlmConfig.load(file: file);
      expect(cfg.defaultDevice, isNull);
    });
  });

  group('LlmConfig.save', () {
    test('round-trip: defaultDevice survives save → load', () {
      LlmConfig(defaultDevice: '/dev/llm/anthropic/claude-sonnet-4')
          .save(file: file);
      expect(LlmConfig.load(file: file).defaultDevice,
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('round-trip: aliases survive save → load', () {
      LlmConfig(
          aliases: {'sonnet': '/dev/llm/anthropic/claude-sonnet-4'}).save(
          file: file);
      expect(LlmConfig.load(file: file).aliases['sonnet'],
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('empty config writes valid JSON with no null fields', () {
      LlmConfig().save(file: file);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json.containsKey('default'), isFalse);
      expect(json.containsKey('aliases'), isFalse);
    });

    test('save creates parent directories that do not exist', () {
      final deep = File('${tmp.path}/a/b/c/config.json');
      LlmConfig(defaultDevice: '/dev/llm/openai/gpt-4o-mini').save(file: deep);
      expect(deep.existsSync(), isTrue);
    });
  });

  group('alias management', () {
    test('adding an alias and saving persists it', () {
      final cfg = LlmConfig();
      cfg.aliases['sonnet'] = '/dev/llm/anthropic/claude-sonnet-4';
      cfg.save(file: file);
      expect(LlmConfig.load(file: file).aliases['sonnet'],
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('overwriting an alias replaces the old value', () {
      file.writeAsStringSync(
          jsonEncode({'aliases': {'x': '/dev/llm/openai/gpt-4o-mini'}}));
      final cfg = LlmConfig.load(file: file);
      cfg.aliases['x'] = '/dev/llm/anthropic/claude-sonnet-4';
      cfg.save(file: file);
      expect(LlmConfig.load(file: file).aliases['x'],
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('setting defaultDevice on a loaded config persists on save', () {
      final cfg = LlmConfig.load(file: file); // empty
      cfg.defaultDevice = '/dev/llm/anthropic/claude-sonnet-4';
      cfg.save(file: file);
      expect(LlmConfig.load(file: file).defaultDevice,
          '/dev/llm/anthropic/claude-sonnet-4');
    });
  });
}
