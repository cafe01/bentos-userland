/// Tests for chat-codec subcommands.
/// Uses in-process command construction with injectable StringSink for output.
library;

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat/chat.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<({int exitCode, String out})> runChatCodec(
  List<String> args, {
  StringBuffer? outBuf,
}) async {
  final buf = outBuf ?? StringBuffer();
  final runner = _buildTestRunner(buf);
  final exitCode = await runner.run(args) ?? 0;
  return (exitCode: exitCode, out: buf.toString());
}

CommandRunner<int> _buildTestRunner(StringBuffer buf) {
  final runner = CommandRunner<int>('chat-codec', 'test runner');
  runner
    ..addCommand(MessageCommand()..out = buf)
    ..addCommand(ContentCommand()..out = buf);
  return runner;
}

// ---------------------------------------------------------------------------
// chat-codec message
// ---------------------------------------------------------------------------

void main() {
  group('chat-codec message', () {
    test('--user emits a user ChatMessage JSON line', () async {
      final r = await runChatCodec(['message', '--user', 'hello world']);
      expect(r.exitCode, 0);
      final line = r.out.trimRight();
      expect(line.contains('\n'), isFalse, reason: 'must be one line');
      final msg = decodeMessageJson(line);
      expect(msg.role, ChatRole.user);
      expect((msg.content.first as TextContent).text, 'hello world');
    });

    test('--system emits a system ChatMessage', () async {
      final r = await runChatCodec(['message', '--system', 'be terse']);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.system);
      expect((msg.content.first as TextContent).text, 'be terse');
    });

    test('--assistant emits an assistant ChatMessage', () async {
      final r = await runChatCodec(['message', '--assistant', 'sure']);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.assistant);
      expect((msg.content.first as TextContent).text, 'sure');
    });

    test('no role flag throws UsageException', () {
      final runner = _buildTestRunner(StringBuffer());
      expect(
        () => runner.run(['message']),
        throwsA(isA<UsageException>()),
      );
    });

    test('two role flags throws UsageException', () {
      final runner = _buildTestRunner(StringBuffer());
      expect(
        () => runner.run(['message', '--user', 'hi', '--system', 'sys']),
        throwsA(isA<UsageException>()),
      );
    });

    test('round-trip: encodes and decodes with structural identity', () async {
      const text = 'explain the Matter protocol in one sentence';
      final r = await runChatCodec(['message', '--user', text]);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.user);
      expect((msg.content.first as TextContent).text, text);
    });

    test('output is valid input for llm --input-format jsonl', () async {
      const text = 'what is bentos?';
      final r = await runChatCodec(['message', '--user', text]);
      expect(() => decodeMessageJson(r.out.trimRight()), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // chat-codec content
  // ---------------------------------------------------------------------------

  group('chat-codec content', () {
    test('--text emits a TextContent JSONL line (NOT a ChatMessage)', () async {
      final r = await runChatCodec(['content', '--text', 'hello block']);
      expect(r.exitCode, 0);
      final line = r.out.trimRight();
      expect(line.contains('\n'), isFalse, reason: 'must be one line');
      final content = decodeContentJson(line);
      expect(content, isA<TextContent>());
      expect((content as TextContent).text, 'hello block');
    });

    test('output is NOT decodable as a ChatMessage', () async {
      final r = await runChatCodec(['content', '--text', 'raw block']);
      expect(
        () => decodeMessageJson(r.out.trimRight()),
        throwsA(anything),
        reason: 'content altitude must not produce a ChatMessage envelope',
      );
    });

    test('round-trip: encodes and decodes with structural identity', () async {
      const text = 'explain the Matter protocol in one sentence';
      final r = await runChatCodec(['content', '--text', text]);
      final content = decodeContentJson(r.out.trimRight());
      expect(content, isA<TextContent>());
      expect((content as TextContent).text, text);
    });

    test('no --text flag throws UsageException', () {
      final runner = _buildTestRunner(StringBuffer());
      expect(
        () => runner.run(['content']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
