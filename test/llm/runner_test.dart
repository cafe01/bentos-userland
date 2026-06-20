import 'package:bentos_userland/llm.dart';
import 'package:test/test.dart';

void main() {
  group('LlmRunner', () {
    test('--version exits 0', () async {
      expect(await LlmRunner().run(['--version']), 0);
    });

    test('bare invocation prints usage and exits 0', () async {
      expect(await LlmRunner().run([]), 0);
    });

    test('an unknown top-level flag is a usage error (exit 64)', () async {
      expect(await LlmRunner().run(['--nope']), 64);
    });

    test('registers prompt and chat commands', () {
      final runner = LlmRunner();
      expect(runner.commands.keys, containsAll(['prompt', 'chat']));
    });
  });
}
