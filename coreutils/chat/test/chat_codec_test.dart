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
    ..addCommand(ContentCommand()..out = buf)
    ..addCommand(EventCommand()..out = buf);
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

  // ---------------------------------------------------------------------------
  // chat-codec event
  // ---------------------------------------------------------------------------

  group('chat-codec event', () {
    test('text_start emits TextStart', () async {
      final r = await runChatCodec(['event', 'text_start']);
      expect(r.exitCode, 0);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<TextStart>());
    });

    test('text_delta:Hello emits TextDelta with correct text', () async {
      final r = await runChatCodec(['event', 'text_delta:Hello']);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<TextDelta>());
      expect((ev as TextDelta).text, 'Hello');
    });

    test('text_stop emits TextStop', () async {
      final r = await runChatCodec(['event', 'text_stop']);
      expect(decodeEventJson(r.out.trimRight()), isA<TextStop>());
    });

    test('multiple tokens emit one JSON line each', () async {
      final r = await runChatCodec([
        'event',
        'text_start',
        'text_delta:Hi',
        'text_stop',
        'complete',
      ]);
      final lines =
          r.out.trimRight().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(4));
      expect(decodeEventJson(lines[0]), isA<TextStart>());
      expect(decodeEventJson(lines[1]), isA<TextDelta>());
      expect(decodeEventJson(lines[2]), isA<TextStop>());
      expect(decodeEventJson(lines[3]), isA<Complete>());
    });

    test('complete uses stub metadata by default', () async {
      final r = await runChatCodec(['event', 'complete']);
      final ev = decodeEventJson(r.out.trimRight()) as Complete;
      expect(ev.metadata.model, 'stub');
      expect(ev.metadata.stopReason, isA<EndTurn>());
    });

    test('complete:mymodel:max_tokens uses provided metadata', () async {
      final r = await runChatCodec(['event', 'complete:mymodel:max_tokens']);
      final ev = decodeEventJson(r.out.trimRight()) as Complete;
      expect(ev.metadata.model, 'mymodel');
      expect(ev.metadata.stopReason, isA<MaxTokens>());
    });

    test('fn_start:call1:get_weather emits FunctionCallStart', () async {
      final r = await runChatCodec(['event', 'fn_start:call1:get_weather']);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<FunctionCallStart>());
      expect((ev as FunctionCallStart).id, 'call1');
      expect(ev.name, 'get_weather');
    });

    test('fn_args emits FunctionArgsDelta', () async {
      final r = await runChatCodec(['event', 'fn_args:{"q":"bentos"}']);
      final ev = decodeEventJson(r.out.trimRight()) as FunctionArgsDelta;
      expect(ev.partialJson, '{"q":"bentos"}');
    });

    test('fn_stop emits FunctionCallStop', () async {
      final r = await runChatCodec(['event', 'fn_stop']);
      expect(decodeEventJson(r.out.trimRight()), isA<FunctionCallStop>());
    });

    test('thinking_start/delta/stop emits correct events', () async {
      final r = await runChatCodec([
        'event',
        'thinking_start',
        'thinking_delta:let me think',
        'thinking_stop',
      ]);
      final lines =
          r.out.trimRight().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(3));
      expect(decodeEventJson(lines[0]), isA<ThinkingStart>());
      expect(decodeEventJson(lines[1]), isA<ThinkingDelta>());
      expect(decodeEventJson(lines[2]), isA<ThinkingStop>());
    });

    test('fixture DSL: every line round-trips through decodeEventJson', () async {
      final r = await runChatCodec([
        'event',
        'text_start',
        'text_delta:part one ',
        'text_delta:part two',
        'text_stop',
        'complete:fixture-model:end_turn',
      ]);
      final lines =
          r.out.trimRight().split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(5));
      for (final line in lines) {
        expect(() => decodeEventJson(line), returnsNormally);
      }
    });
  });
}
