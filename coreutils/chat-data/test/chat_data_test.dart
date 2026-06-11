/// Tests for chat-data subcommands.
/// Uses in-process command construction with injectable StringSink for output.
library;

import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat_data/chat_data.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers — run a command with captured output.
// ---------------------------------------------------------------------------

/// Run chat-data subcommand args through the runner, returning the stdout
/// captured via the injectable sink on the leaf command.
Future<({int exitCode, String out})> runChatData(
  List<String> args, {
  StringBuffer? outBuf,
}) async {
  final buf = outBuf ?? StringBuffer();
  final runner = _buildTestRunner(buf);
  final exitCode = await runner.run(args) ?? 0;
  return (exitCode: exitCode, out: buf.toString());
}

/// Build a runner where all commands share the same injectable output sink.
CommandRunner<int> _buildTestRunner(StringBuffer buf) {
  final runner = CommandRunner<int>('chat-data', 'test runner');
  runner
    ..addCommand(MsgCommand()..out = buf)
    ..addCommand(EventCommand()..out = buf)
    ..addCommand(ValidateCommand())
    ..addCommand(FoldCommand());
  return runner;
}

// ---------------------------------------------------------------------------
// In-process fold: decodes JSONL events and folds them to a ChatMessage.
// ---------------------------------------------------------------------------

Future<ChatMessage> _foldJsonl(String jsonl) async {
  final controller = StreamController<ChatEvent>();
  for (final line in const LineSplitter().convert(jsonl)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) controller.add(decodeEventJson(trimmed));
  }
  controller.close();
  return controller.stream.foldToMessage();
}

// ---------------------------------------------------------------------------
// In-process validate: returns number of invalid lines.
// ---------------------------------------------------------------------------

int _countErrors(String jsonl) {
  var errors = 0;
  for (final line in const LineSplitter().convert(jsonl)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    try {
      decodeEventJson(trimmed);
    } catch (_) {
      errors++;
    }
  }
  return errors;
}

// ---------------------------------------------------------------------------
// msg subcommand
// ---------------------------------------------------------------------------

void main() {
  group('chat-data msg', () {
    test('--user emits a user ChatMessage JSON line', () async {
      final r = await runChatData(['msg', '--user', 'hello world']);
      expect(r.exitCode, 0);
      final line = r.out.trimRight();
      expect(line.contains('\n'), isFalse, reason: 'must be one line');
      final msg = decodeMessageJson(line);
      expect(msg.role, ChatRole.user);
      expect((msg.content.first as TextContent).text, 'hello world');
    });

    test('--system emits a system ChatMessage', () async {
      final r = await runChatData(['msg', '--system', 'be terse']);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.system);
      expect((msg.content.first as TextContent).text, 'be terse');
    });

    test('--assistant emits an assistant ChatMessage', () async {
      final r = await runChatData(['msg', '--assistant', 'sure']);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.assistant);
      expect((msg.content.first as TextContent).text, 'sure');
    });

    test('no role flag throws UsageException', () {
      final runner = _buildTestRunner(StringBuffer());
      expect(
        () => runner.run(['msg']),
        throwsA(isA<UsageException>()),
      );
    });

    test('two role flags throws UsageException', () {
      final runner = _buildTestRunner(StringBuffer());
      expect(
        () => runner.run(['msg', '--user', 'hi', '--system', 'sys']),
        throwsA(isA<UsageException>()),
      );
    });

    test('round-trip: encodes and decodes with structural identity', () async {
      const text = 'explain the Matter protocol in one sentence';
      final r = await runChatData(['msg', '--user', text]);
      final msg = decodeMessageJson(r.out.trimRight());
      expect(msg.role, ChatRole.user);
      expect((msg.content.first as TextContent).text, text);
    });

    test('prompt-box use case: output is valid input for llm --input-format jsonl',
        () async {
      const text = 'what is bentos?';
      final r = await runChatData(['msg', '--user', text]);
      // The line must be decodable as a ChatMessage — the jsonl input contract.
      expect(() => decodeMessageJson(r.out.trimRight()), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // event subcommand
  // -------------------------------------------------------------------------

  group('chat-data event', () {
    test('text_start emits TextStart', () async {
      final r = await runChatData(['event', 'text_start']);
      expect(r.exitCode, 0);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<TextStart>());
    });

    test('text_delta:Hello emits TextDelta with correct text', () async {
      final r = await runChatData(['event', 'text_delta:Hello']);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<TextDelta>());
      expect((ev as TextDelta).text, 'Hello');
    });

    test('text_stop emits TextStop', () async {
      final r = await runChatData(['event', 'text_stop']);
      expect(decodeEventJson(r.out.trimRight()), isA<TextStop>());
    });

    test('multiple tokens emit one JSON line each', () async {
      final r = await runChatData([
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
      final r = await runChatData(['event', 'complete']);
      final ev = decodeEventJson(r.out.trimRight()) as Complete;
      expect(ev.metadata.model, 'stub');
      expect(ev.metadata.stopReason, isA<EndTurn>());
    });

    test('complete:mymodel:max_tokens uses provided metadata', () async {
      final r = await runChatData(['event', 'complete:mymodel:max_tokens']);
      final ev = decodeEventJson(r.out.trimRight()) as Complete;
      expect(ev.metadata.model, 'mymodel');
      expect(ev.metadata.stopReason, isA<MaxTokens>());
    });

    test('fn_start:call1:get_weather emits FunctionCallStart', () async {
      final r = await runChatData(['event', 'fn_start:call1:get_weather']);
      final ev = decodeEventJson(r.out.trimRight());
      expect(ev, isA<FunctionCallStart>());
      expect((ev as FunctionCallStart).id, 'call1');
      expect(ev.name, 'get_weather');
    });

    test('fn_args emits FunctionArgsDelta', () async {
      final r = await runChatData(['event', 'fn_args:{"q":"bentos"}']);
      final ev = decodeEventJson(r.out.trimRight()) as FunctionArgsDelta;
      expect(ev.partialJson, '{"q":"bentos"}');
    });

    test('fn_stop emits FunctionCallStop', () async {
      final r = await runChatData(['event', 'fn_stop']);
      expect(decodeEventJson(r.out.trimRight()), isA<FunctionCallStop>());
    });

    test('thinking_start/delta/stop emits correct events', () async {
      final r = await runChatData([
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
      final r = await runChatData([
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

  // -------------------------------------------------------------------------
  // fold (in-process via stream helper)
  // -------------------------------------------------------------------------

  group('chat-data fold', () {
    test('folds text event stream to assistant ChatMessage', () async {
      final events = [
        const TextStart(0),
        const TextDelta(index: 0, text: 'Hello'),
        const TextDelta(index: 0, text: ', world!'),
        const TextStop(0),
        Complete(ChatMetadata(model: 'test', stopReason: const EndTurn())),
      ];
      final msg = await _foldJsonl(events.map(encodeEventJson).join('\n'));
      expect(msg.role, ChatRole.assistant);
      expect((msg.content.first as TextContent).text, 'Hello, world!');
    });

    test('folds function-call event stream to assistant ChatMessage', () async {
      final events = [
        const FunctionCallStart(index: 0, id: 'c1', name: 'search'),
        const FunctionArgsDelta(index: 0, partialJson: '{"q":"bentos"}'),
        const FunctionCallStop(0),
        Complete(ChatMetadata(model: 'test', stopReason: const FunctionCall())),
      ];
      final msg = await _foldJsonl(events.map(encodeEventJson).join('\n'));
      expect(msg.role, ChatRole.assistant);
      final call = msg.content.first as FunctionCallContent;
      expect(call.name, 'search');
      expect(call.arguments, {'q': 'bentos'});
    });

    test('pipeline: event DSL → fold → ChatMessage (full compose)', () async {
      // Simulate: chat-data event … | chat-data fold
      final buf = StringBuffer();
      await runChatData([
        'event',
        'text_start',
        'text_delta:the answer',
        'text_stop',
        'complete',
      ], outBuf: buf);

      final msg = await _foldJsonl(buf.toString().trimRight());
      expect(msg.role, ChatRole.assistant);
      expect((msg.content.first as TextContent).text, 'the answer');
    });

    test('fold output is a valid ChatMessage JSONL line', () async {
      final events = [
        const TextStart(0),
        const TextDelta(index: 0, text: 'ok'),
        const TextStop(0),
        Complete(ChatMetadata(model: 'm', stopReason: const EndTurn())),
      ];
      final msg = await _foldJsonl(events.map(encodeEventJson).join('\n'));
      final line = encodeMessageJson(msg);
      expect(line.contains('\n'), isFalse, reason: 'must be one line');
      expect(() => decodeMessageJson(line), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // validate (in-process via helper)
  // -------------------------------------------------------------------------

  group('chat-data validate', () {
    test('valid event stream has zero errors', () {
      final events = [
        const TextStart(0),
        const TextDelta(index: 0, text: 'hi'),
        const TextStop(0),
        Complete(ChatMetadata(model: 'x', stopReason: const EndTurn())),
      ];
      expect(_countErrors(events.map(encodeEventJson).join('\n')), 0);
    });

    test('invalid line is counted as an error', () {
      final jsonl =
          '${encodeEventJson(const TextStart(0))}\nnot-valid-json\n';
      expect(_countErrors(jsonl), 1);
    });

    test('empty lines are ignored', () {
      final events = [const TextStart(0), const TextStop(0)];
      final jsonl = '\n${events.map(encodeEventJson).join('\n\n')}\n\n';
      expect(_countErrors(jsonl), 0);
    });

    test('multiple invalid lines all counted', () {
      final jsonl = 'bad1\nbad2\n${encodeEventJson(const TextStart(0))}\nbad3';
      expect(_countErrors(jsonl), 3);
    });
  });
}
