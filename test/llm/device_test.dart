import 'package:bentos_userland/llm.dart';
import 'package:test/test.dart';

void main() {
  group('resolveDevicePath precedence', () {
    test('explicit arg wins over env and default', () {
      expect(
        resolveDevicePath('/dev/llm/anthropic/claude-haiku-4-5',
            environment: {deviceEnvVar: '/dev/llm/openai/gpt-4o'}),
        '/dev/llm/anthropic/claude-haiku-4-5',
      );
    });

    test('env wins over default when no explicit arg', () {
      expect(
        resolveDevicePath(null,
            environment: {deviceEnvVar: '/dev/llm/openai/gpt-4o'}),
        '/dev/llm/openai/gpt-4o',
      );
    });

    test('default when neither arg nor env is set', () {
      expect(resolveDevicePath(null), defaultDevicePath);
    });

    test('empty explicit / empty env fall through', () {
      expect(resolveDevicePath('', environment: {deviceEnvVar: ''}),
          defaultDevicePath);
    });
  });

  group('normalizeDevicePath', () {
    test('short vendor/model gets /dev/llm/ prefix', () {
      expect(normalizeDevicePath('openai/gpt-4o-mini'),
          '/dev/llm/openai/gpt-4o-mini');
    });

    test('full /dev/llm/… path passes through unchanged', () {
      expect(normalizeDevicePath('/dev/llm/openai/gpt-4o-mini'),
          '/dev/llm/openai/gpt-4o-mini');
    });
  });

  group('resolveDevicePath with LlmConfig', () {
    LlmConfig cfg({String? def, Map<String, String> aliases = const {}}) =>
        LlmConfig(defaultDevice: def, aliases: Map.of(aliases));

    test('explicit alias is resolved to its full path', () {
      final c = cfg(aliases: {'sonnet': '/dev/llm/anthropic/claude-sonnet-4'});
      expect(resolveDevicePath('sonnet', config: c),
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('non-alias short arg is normalised', () {
      expect(resolveDevicePath('openai/gpt-4o', config: cfg()),
          '/dev/llm/openai/gpt-4o');
    });

    test('configured default wins over built-in when no arg/env', () {
      final c = cfg(def: '/dev/llm/anthropic/claude-sonnet-4');
      expect(resolveDevicePath(null, config: c),
          '/dev/llm/anthropic/claude-sonnet-4');
    });

    test('explicit arg wins over configured default', () {
      final c = cfg(def: '/dev/llm/anthropic/claude-sonnet-4');
      expect(resolveDevicePath('openai/gpt-4o-mini', config: c),
          '/dev/llm/openai/gpt-4o-mini');
    });

    test('env wins over configured default', () {
      final c = cfg(def: '/dev/llm/anthropic/claude-sonnet-4');
      expect(
        resolveDevicePath(null,
            environment: {deviceEnvVar: '/dev/llm/openai/gpt-4o'},
            config: c),
        '/dev/llm/openai/gpt-4o',
      );
    });

    test('null config falls through to built-in default', () {
      expect(resolveDevicePath(null, config: null), defaultDevicePath);
    });
  });
}
