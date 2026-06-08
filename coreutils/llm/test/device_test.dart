import 'package:llm/llm.dart';
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
}
