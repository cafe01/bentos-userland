import 'package:llm/llm.dart';
import 'package:test/test.dart';

void main() {
  // The set the runner passes: its real command names plus the auto-added help.
  const known = {'prompt', 'chat', 'models', 'help'};

  group('withDefaultCommand routing', () {
    test('bare prompt routes to the default command', () {
      expect(withDefaultCommand(['what is bentos?'], known),
          ['prompt', 'what is bentos?']);
    });

    test('multi-word prompt is preserved after the inserted command', () {
      expect(withDefaultCommand(['what', 'is', 'bentos'], known),
          ['prompt', 'what', 'is', 'bentos']);
    });

    test('a flag before the prompt is kept under the default command', () {
      expect(withDefaultCommand(['-v', 'hello'], known),
          ['prompt', '-v', 'hello']);
    });

    test('explicit command is left untouched', () {
      expect(withDefaultCommand(['chat'], known), ['chat']);
      expect(withDefaultCommand(['chat', '-v'], known), ['chat', '-v']);
    });

    test('help command is left untouched', () {
      expect(withDefaultCommand(['help'], known), ['help']);
    });

    test('flag-only invocation (e.g. --version, -h) is left for the runner', () {
      expect(withDefaultCommand(['--version'], known), ['--version']);
      expect(withDefaultCommand(['-h'], known), ['-h']);
    });

    test('empty invocation is left untouched', () {
      expect(withDefaultCommand([], known), isEmpty);
    });

    test('piped stdin routes a bare invocation to the default command', () {
      expect(withDefaultCommand([], known, stdinHasPrompt: true), ['prompt']);
      expect(withDefaultCommand(['-v'], known, stdinHasPrompt: true),
          ['prompt', '-v']);
    });

    test('an explicit command with piped stdin is still left untouched', () {
      expect(withDefaultCommand(['chat'], known, stdinHasPrompt: true),
          ['chat']);
    });
  });
}
