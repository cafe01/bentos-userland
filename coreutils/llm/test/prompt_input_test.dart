/// Tests for PromptCommand's jsonl input/output modes:
/// - Input: line-by-line decoding turns a JSONL conversation into ChatMessages.
/// - Output: filterTurn emits one JSON line per turn and round-trips correctly.
/// - D2: FunctionDefinition loading from JSON files, function-choice wiring,
///   and a full turn with a scripted function-call reply.
///
/// filterTurn tests use a scripted in-process driver (BentosDriver) so they
/// run without any network or API key.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:fixnum/fixnum.dart';
import 'package:llm/llm.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers — codec pipeline (same as PromptCommand._resolveJsonlMessages).
// ---------------------------------------------------------------------------

List<ChatMessage> parseJsonlConversation(String jsonl) {
  return jsonl
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .map(decodeMessageJson)
      .toList();
}

// ---------------------------------------------------------------------------
// Scripted driver builder.
// Returns an InertConsumer whose device emits the given script of ChatEvents.
// ---------------------------------------------------------------------------

InertConsumer _makeConsumer(List<ChatEvent> script) {
  var cursor = 0;

  final driver = BentosDriver(
    onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
    onIoctl: (req, ctx) => FuseResponse(ioctl: IoctlReply()),
    onWrite: (req, ctx) =>
        FuseResponse(write: WriteReply(count: Int64(req.data.length))),
    onRead: (req, ctx) => FuseResponse(
      buf: BufReply(
        data: cursor < script.length
            ? encodeEventFrame(script[cursor++])
            : Uint8List(0),
      ),
    ),
    onFlush: (req, ctx) => FuseResponse(),
    onRelease: (req, ctx) => FuseResponse(),
  );

  final pair = StreamChannelController<Uint8List>();
  driver.serveChannel(pair.foreign);
  final device = BentosChatDevice(
    InProcessBentos(capMap: {'/dev/llm/': pair.local}),
    '/dev/llm/test/scripted',
  );
  return InertConsumer(device);
}

final _metadata = ChatMetadata(
  model: 'test-1',
  stopReason: const EndTurn(),
  usage: const TokenUsage(inputTokens: 3, outputTokens: 5),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('jsonl input mode — line decoding', () {
    test('single user message round-trips', () {
      const m = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('hello')],
      );
      final line = encodeMessageJson(m);
      final result = parseJsonlConversation(line);
      expect(result, hasLength(1));
      expect(result.first, equals(m));
    });

    test('multi-turn conversation preserves order and roles', () {
      const messages = [
        ChatMessage(role: ChatRole.user, content: [TextContent('turn 1')]),
        ChatMessage(role: ChatRole.assistant, content: [TextContent('reply 1')]),
        ChatMessage(role: ChatRole.user, content: [TextContent('turn 2')]),
      ];
      final jsonl = messages.map(encodeMessageJson).join('\n');
      final result = parseJsonlConversation(jsonl);
      expect(result, equals(messages));
    });

    test('blank lines between messages are ignored', () {
      const m = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('hello')],
      );
      final line = encodeMessageJson(m);
      final jsonl = '\n$line\n\n';
      final result = parseJsonlConversation(jsonl);
      expect(result, hasLength(1));
      expect(result.first, equals(m));
    });

    test('message with function call decodes correctly', () {
      const m = ChatMessage(
        role: ChatRole.assistant,
        content: [
          FunctionCallContent(
            id: 'call_1',
            name: 'get_weather',
            arguments: {'city': 'Tokyo'},
          ),
        ],
      );
      final result = parseJsonlConversation(encodeMessageJson(m));
      expect(result.first, equals(m));
    });

    test('heterogeneous message (text + function call) decodes correctly', () {
      const m = ChatMessage(
        role: ChatRole.assistant,
        content: [
          TextContent("I'll check that."),
          FunctionCallContent(
            id: 'call_2',
            name: 'search',
            arguments: {'q': 'BentOS'},
          ),
        ],
      );
      final result = parseJsonlConversation(encodeMessageJson(m));
      expect(result.first, equals(m));
    });

    test('filter pipeline (headline use-case): conversation with tool result', () {
      const conversation = [
        ChatMessage(
          role: ChatRole.user,
          content: [TextContent('What is the weather in SP?')],
        ),
        ChatMessage(
          role: ChatRole.assistant,
          content: [
            FunctionCallContent(
              id: 'call_x',
              name: 'get_weather',
              arguments: {'city': 'São Paulo'},
            ),
          ],
        ),
        ChatMessage(
          role: ChatRole.user,
          content: [
            FunctionResultContent(
              callId: 'call_x',
              content: [TextContent('28°C and sunny')],
              isError: false,
            ),
          ],
        ),
      ];
      final jsonl = conversation.map(encodeMessageJson).join('\n');
      final result = parseJsonlConversation(jsonl);
      expect(result, equals(conversation));
    });
  });

  group('jsonl output mode — filterTurn', () {
    test('text reply emits one JSON line, round-trips to assistant ChatMessage',
        () async {
      final consumer = _makeConsumer([
        const TextStart(0),
        const TextDelta(index: 0, text: 'Hello, '),
        const TextDelta(index: 0, text: 'world!'),
        const TextStop(0),
        Complete(_metadata),
      ]);

      final out = StringBuffer();
      final message = await consumer.filterTurn(
        [const ChatMessage(role: ChatRole.user, content: [TextContent('hi')])],
        out: out,
      );

      final line = out.toString().trim();
      expect(line.contains('\n'), isFalse,
          reason: 'filterTurn must emit exactly one line');
      expect(line.startsWith('{'), isTrue);

      final decoded = decodeMessageJson(line);
      expect(decoded.role, ChatRole.assistant);
      expect(decoded, equals(message));
      expect((decoded.content.first as TextContent).text, 'Hello, world!');
    });

    test('function-call reply emits one JSON line with FunctionCallContent',
        () async {
      final consumer = _makeConsumer([
        const FunctionCallStart(index: 0, id: 'call_1', name: 'lookup'),
        const FunctionArgsDelta(index: 0, partialJson: '{"q":"b'),
        const FunctionArgsDelta(index: 0, partialJson: 'entos"}'),
        const FunctionCallStop(0),
        Complete(_metadata),
      ]);

      final out = StringBuffer();
      final message = await consumer.filterTurn(
        [const ChatMessage(role: ChatRole.user, content: [TextContent('search')])],
        out: out,
      );

      final decoded = decodeMessageJson(out.toString().trim());
      expect(decoded.role, ChatRole.assistant);
      expect(decoded.content, hasLength(1));
      final call = decoded.content.first as FunctionCallContent;
      expect(call.name, 'lookup');
      expect(call.arguments, {'q': 'bentos'});
      expect(decoded, equals(message));
    });

    test('heterogeneous reply (text + function call) assembles all contents',
        () async {
      final consumer = _makeConsumer([
        const TextStart(0),
        const TextDelta(index: 0, text: "I'll look that up."),
        const TextStop(0),
        const FunctionCallStart(index: 1, id: 'call_2', name: 'search'),
        const FunctionArgsDelta(index: 1, partialJson: '{"q":"dart"}'),
        const FunctionCallStop(1),
        Complete(_metadata),
      ]);

      final out = StringBuffer();
      final message = await consumer.filterTurn(
        [const ChatMessage(role: ChatRole.user, content: [TextContent('search dart')])],
        out: out,
      );

      final decoded = decodeMessageJson(out.toString().trim());
      expect(decoded.content, hasLength(2));
      expect(decoded.content[0], isA<TextContent>());
      expect(decoded.content[1], isA<FunctionCallContent>());
      expect(decoded, equals(message));
    });

    test('filter pipeline end-to-end: input jsonl → filterTurn → output jsonl',
        () async {
      // Simulates: cat messages.jsonl | llm --input-format jsonl --output-format jsonl
      const inputConversation = [
        ChatMessage(role: ChatRole.user, content: [TextContent('first turn')]),
        ChatMessage(
            role: ChatRole.assistant, content: [TextContent('first reply')]),
        ChatMessage(role: ChatRole.user, content: [TextContent('second turn')]),
      ];

      final consumer = _makeConsumer([
        const TextStart(0),
        const TextDelta(index: 0, text: 'second reply'),
        const TextStop(0),
        Complete(_metadata),
      ]);

      // Step 1: parse input jsonl (PromptCommand._resolveJsonlMessages)
      final jsonl = inputConversation.map(encodeMessageJson).join('\n');
      final messages = parseJsonlConversation(jsonl);
      expect(messages, equals(inputConversation));

      // Step 2: run the turn (filterTurn)
      final out = StringBuffer();
      await consumer.filterTurn(messages, out: out);

      // Step 3: decode output line (what >> messages.jsonl captures)
      final outputLine = out.toString().trim();
      final reply = decodeMessageJson(outputLine);
      expect(reply.role, ChatRole.assistant);
      expect((reply.content.first as TextContent).text, 'second reply');
    });
  });

  // ---------------------------------------------------------------------------
  // D2 — function calling: file loading + ioConfig wiring + full turn
  // ---------------------------------------------------------------------------

  group('D2 — FunctionDefinition loading from JSON file', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('llm_d2_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File writeJson(String name, Map<String, dynamic> content) {
      final f = File('${tmp.path}/$name');
      f.writeAsStringSync(jsonEncode(content));
      return f;
    }

    test('valid JSON file is parsed into FunctionDefinition', () {
      final f = writeJson('weather.json', {
        'name': 'get_weather',
        'description': 'Get current weather for a city.',
        'inputSchema': {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
          'required': ['city'],
        },
      });
      final def = loadFunctionDefinitionFromFile(f.path);
      expect(def.name, 'get_weather');
      expect(def.description, 'Get current weather for a city.');
      expect(def.inputSchema['type'], 'object');
      expect(
        (def.inputSchema['properties'] as Map)['city'],
        {'type': 'string'},
      );
    });

    test('multiple files produce a list in declaration order', () {
      final f1 = writeJson('fn1.json', {
        'name': 'alpha',
        'description': 'First.',
        'inputSchema': <String, dynamic>{},
      });
      final f2 = writeJson('fn2.json', {
        'name': 'beta',
        'description': 'Second.',
        'inputSchema': <String, dynamic>{},
      });
      final defs = [f1.path, f2.path].map(loadFunctionDefinitionFromFile).toList();
      expect(defs.map((d) => d.name), ['alpha', 'beta']);
    });

    test('missing file throws ArgumentError', () {
      expect(
        () => loadFunctionDefinitionFromFile('${tmp.path}/nonexistent.json'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('malformed JSON throws FormatException', () {
      final f = File('${tmp.path}/bad.json')..writeAsStringSync('{not json}');
      expect(
        () => loadFunctionDefinitionFromFile(f.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('JSON missing required fields throws ArgumentError', () {
      final f = writeJson('incomplete.json', {'name': 'foo'});
      expect(
        () => loadFunctionDefinitionFromFile(f.path),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('D2 — function calling full turn: scripted driver → jsonl output', () {
    test('driver reply with FunctionCallContent serializes to one jsonl line',
        () async {
      final consumer = _makeConsumer([
        const FunctionCallStart(index: 0, id: 'call_w1', name: 'get_weather'),
        const FunctionArgsDelta(index: 0, partialJson: '{"city":"'),
        const FunctionArgsDelta(index: 0, partialJson: 'Tokyo"}'),
        const FunctionCallStop(0),
        Complete(_metadata),
      ]);

      final out = StringBuffer();
      final message = await consumer.filterTurn(
        [
          const ChatMessage(
            role: ChatRole.user,
            content: [TextContent("What's the weather in Tokyo?")],
          ),
        ],
        out: out,
      );

      final line = out.toString().trim();
      // Must be exactly one line — the shell-loop `>> messages.jsonl` contract.
      expect(line.contains('\n'), isFalse,
          reason: 'filterTurn must emit exactly one line');

      final decoded = decodeMessageJson(line);
      expect(decoded.role, ChatRole.assistant);
      expect(decoded.content, hasLength(1));

      final call = decoded.content.first as FunctionCallContent;
      expect(call.id, 'call_w1');
      expect(call.name, 'get_weather');
      expect(call.arguments, {'city': 'Tokyo'});

      // filterTurn return value == decoded line.
      expect(decoded, equals(message));
    });

    test('wiring: functions and functionChoice flow into ChatIOConfig', () {
      // Validates that the FunctionDefinition list and FunctionChoice
      // are surfaced correctly when copyWith'd — exercises the substrate contract.
      const def = FunctionDefinition(
        name: 'search',
        description: 'Search the web.',
        inputSchema: {'type': 'object'},
      );
      final config = const ChatIOConfig().copyWith(
        functions: [def],
        functionChoice: const AutoChoice(),
      );
      expect(config.functions, hasLength(1));
      expect(config.functions!.first.name, 'search');
      expect(config.functionChoice, isA<AutoChoice>());
    });
  });
}
