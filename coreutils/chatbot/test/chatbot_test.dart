import 'package:chatbot/chatbot.dart';
import 'package:test/test.dart';

void main() {
  group('withDefaultCommand — bare/single-shot routing', () {
    const known = {'chat', 'resume', 'list', 'show'};

    test('empty args route to the chat REPL', () {
      expect(withDefaultCommand([], known), equals(['chat']));
    });

    test('a bare prompt becomes a chat single-shot', () {
      expect(
        withDefaultCommand(['hello there'], known),
        equals(['chat', 'hello there']),
      );
    });

    test('a known subcommand passes through untouched', () {
      expect(withDefaultCommand(['resume', 'abc123'], known),
          equals(['resume', 'abc123']));
      expect(withDefaultCommand(['list'], known), equals(['list']));
    });

    test('flags-only (e.g. --version) pass through for the runner', () {
      expect(withDefaultCommand(['--version'], known), equals(['--version']));
    });

    test('a prompt with leading flags still routes to chat', () {
      expect(
        withDefaultCommand(['-v', 'what is 2+2'], known),
        equals(['chat', '-v', 'what is 2+2']),
      );
    });
  });
}
