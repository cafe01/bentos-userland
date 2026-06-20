/// Tests for PromptCommand's typed input/output modes via relayTurn:
/// - Typed input: raw json/protobuf bytes from stdin are written to the device
///   verbatim — never decoded to ChatMessage.
/// - Typed output: raw bytes from device read() are emitted verbatim with the
///   coreutil's framing only (json: +\n; protobuf: +4-byte header).
/// - D2: FunctionDefinition loading from JSON files, function-choice wiring.
///
/// relayTurn tests use a scripted in-process driver (BentosDriver) so they
/// run without any network or API key.
library;

import 'dart:async';
import 'dart:convert' as dc show Encoding, utf8;
import 'dart:convert' show utf8, jsonEncode;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:fixnum/fixnum.dart';
import 'package:llm/llm.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Captured ioctl call.
// ---------------------------------------------------------------------------

class _IoctlCall {
  final int cmd;
  final Uint8List data;
  _IoctlCall(this.cmd, this.data);
}

// ---------------------------------------------------------------------------
// BytesIOSink — injectable output for relayTurn.
// ---------------------------------------------------------------------------

class BytesIOSink implements IOSink {
  final _bytes = BytesBuilder();

  Uint8List get bytes => _bytes.toBytes();

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  void write(Object? object) =>
      _bytes.add(dc.utf8.encode(object?.toString() ?? ''));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final o in objects) {
      if (!first) write(separator);
      write(o);
      first = false;
    }
  }

  @override
  void writeCharCode(int charCode) =>
      _bytes.add([charCode]);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) { _bytes.add(chunk); }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  dc.Encoding get encoding => dc.utf8;

  @override
  set encoding(dc.Encoding value) {}
}

// ---------------------------------------------------------------------------
// Scripted consumer builder.
//
// [onWriteCapture] receives every write() payload (for input zero-codec proof).
// [readScript] is the list of raw byte records the fake driver returns from
// read() in order; the last item should be Uint8List(0) (EOF sentinel).
// ---------------------------------------------------------------------------

InertConsumer _makeConsumerWithIoctlCapture({
  required List<_IoctlCall> ioctls,
  List<Uint8List> readScript = const [],
}) {
  var cursor = 0;
  final driver = BentosDriver(
    onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
    onIoctl: (req, ctx) {
      ioctls.add(_IoctlCall(req.cmd, Uint8List.fromList(req.inBuf)));
      return FuseResponse(ioctl: IoctlReply());
    },
    onWrite: (req, ctx) =>
        FuseResponse(write: WriteReply(count: Int64(req.data.length))),
    onRead: (req, ctx) => FuseResponse(
      buf: BufReply(
        data: cursor < readScript.length
            ? readScript[cursor++]
            : Uint8List(0),
      ),
    ),
    onFlush: (req, ctx) => FuseResponse(),
    onRelease: (req, ctx) => FuseResponse(),
  );
  final pair = StreamChannelController<Uint8List>();
  driver.serveChannel(pair.foreign);
  final inProcess = InProcessBentos(capMap: {'/dev/llm/': pair.local});
  return InertConsumer(inProcess, '/dev/llm/test/scripted');
}

InertConsumer _makeConsumer({
  void Function(Uint8List)? onWriteCapture,
  List<Uint8List> readScript = const [],
}) {
  var cursor = 0;

  final driver = BentosDriver(
    onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
    onIoctl: (req, ctx) => FuseResponse(ioctl: IoctlReply()),
    onWrite: (req, ctx) {
      onWriteCapture?.call(Uint8List.fromList(req.data));
      return FuseResponse(write: WriteReply(count: Int64(req.data.length)));
    },
    onRead: (req, ctx) => FuseResponse(
      buf: BufReply(
        data: cursor < readScript.length
            ? readScript[cursor++]
            : Uint8List(0),
      ),
    ),
    onFlush: (req, ctx) => FuseResponse(),
    onRelease: (req, ctx) => FuseResponse(),
  );

  final pair = StreamChannelController<Uint8List>();
  driver.serveChannel(pair.foreign);
  final inProcess = InProcessBentos(capMap: {'/dev/llm/': pair.local});
  return InertConsumer(inProcess, '/dev/llm/test/scripted');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _metadata = ChatMetadata(
  model: 'test-1',
  stopReason: const EndTurn(),
  usage: const TokenUsage(inputTokens: 3, outputTokens: 5),
);

/// Builds a 4-byte big-endian length-prefix frame around [payload].
Uint8List _frame(Uint8List payload) {
  final out = Uint8List(4 + payload.length);
  ByteData.sublistView(out).setUint32(0, payload.length);
  out.setRange(4, 4 + payload.length, payload);
  return out;
}

/// Builds a stream that emits [data] as a single chunk.
Stream<List<int>> _streamOf(List<int> data) =>
    Stream.fromIterable([Uint8List.fromList(data)]);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('relay input — typed json: zero codec proof', () {
    test('raw json line bytes reach device write() verbatim', () async {
      final writes = <Uint8List>[];
      final consumer = _makeConsumer(
        onWriteCapture: writes.add,
        readScript: [Uint8List(0)],
      );

      const msg = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('hello relay')],
      );
      final jsonLine = encodeMessageJson(msg);
      final lineBytes = Uint8List.fromList(utf8.encode(jsonLine));

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(inputFormat: Format.structured),
        inputEncoding: 'json',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(lineBytes),
      );

      expect(writes, hasLength(1));
      // The bytes written are the raw json line bytes — NOT protobuf.
      expect(writes.first, equals(lineBytes));

      // Zero-codec proof: the codec round-trip produces different bytes.
      final codecBytes = encodeMessage(decodeMessageJson(jsonLine));
      expect(writes.first, isNot(equals(codecBytes)));
    });

    test('multi-turn jsonl: each line is a separate write(), no decode', () async {
      const messages = [
        ChatMessage(role: ChatRole.user, content: [TextContent('turn 1')]),
        ChatMessage(
            role: ChatRole.assistant, content: [TextContent('reply 1')]),
        ChatMessage(role: ChatRole.user, content: [TextContent('turn 2')]),
      ];
      final jsonl = messages.map(encodeMessageJson).join('\n');
      final inputBytes = Uint8List.fromList(utf8.encode(jsonl));

      final writes = <Uint8List>[];
      final consumer = _makeConsumer(
        onWriteCapture: writes.add,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(inputFormat: Format.structured),
        inputEncoding: 'json',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(inputBytes),
      );

      // One write per non-empty line, never decoded.
      expect(writes, hasLength(messages.length));
      for (var i = 0; i < messages.length; i++) {
        final expected = Uint8List.fromList(utf8.encode(encodeMessageJson(messages[i])));
        expect(writes[i], equals(expected));
      }
    });

    test('blank lines between messages are skipped', () async {
      const msg = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('hi')],
      );
      final jsonl = '\n${encodeMessageJson(msg)}\n\n';
      final inputBytes = Uint8List.fromList(utf8.encode(jsonl));

      final writes = <Uint8List>[];
      final consumer = _makeConsumer(
        onWriteCapture: writes.add,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(inputFormat: Format.structured),
        inputEncoding: 'json',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(inputBytes),
      );

      expect(writes, hasLength(1));
    });
  });

  group('relay input — typed protobuf: zero codec proof', () {
    test('protobuf frames: payload bytes reach device write() verbatim', () async {
      const msg = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('proto relay')],
      );
      final payload = encodeMessage(msg);
      final framed = _frame(payload);

      final writes = <Uint8List>[];
      final consumer = _makeConsumer(
        onWriteCapture: writes.add,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          inputFormat: Format.structured,
          inputEncoding: Encoding.protobuf,
        ),
        inputEncoding: 'protobuf',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(framed),
      );

      // The payload bytes (without the 4-byte header) reach the device.
      expect(writes, hasLength(1));
      expect(writes.first, equals(payload));
    });

    test('multiple protobuf frames: each payload is a separate write()', () async {
      const messages = [
        ChatMessage(role: ChatRole.user, content: [TextContent('msg1')]),
        ChatMessage(role: ChatRole.assistant, content: [TextContent('msg2')]),
      ];
      final framed = messages
          .map(encodeMessage)
          .map(_frame)
          .expand((b) => b)
          .toList();

      final writes = <Uint8List>[];
      final consumer = _makeConsumer(
        onWriteCapture: writes.add,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(inputFormat: Format.structured),
        inputEncoding: 'protobuf',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(framed),
      );

      expect(writes, hasLength(messages.length));
      for (var i = 0; i < messages.length; i++) {
        expect(writes[i], equals(encodeMessage(messages[i])));
      }
    });
  });

  group('relay output — json framing: zero codec proof', () {
    test('device bytes + \\n emitted verbatim per record', () async {
      // Simulate driver returning json event bytes (what the real driver does
      // when outputEncoding=json ioctl is set).
      final rawEvents = [
        Uint8List.fromList(utf8.encode('{"textStart":{"index":0}}')),
        Uint8List.fromList(utf8.encode('{"textDelta":{"index":0,"text":"hi"}}')),
        Uint8List.fromList(utf8.encode('{"complete":{"metadata":{"model":"m"}}}')),
      ];
      final consumer = _makeConsumer(
        readScript: [...rawEvents, Uint8List(0)],
      );

      final out = BytesIOSink();
      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(outputFormat: Format.structured),
        inputEncoding: 'protobuf',
        outputEncoding: 'json',
        textPrompt: 'test',
        out: out,
      );

      final output = out.bytes;
      // Reconstruct expected: each raw record + 0x0A ('\n').
      final expected = BytesBuilder();
      for (final r in rawEvents) {
        expected.add(r);
        expected.addByte(10);
      }
      expect(output, equals(expected.toBytes()));
    });

    test('device bytes pass through unchanged (no decode+re-encode cycle)', () async {
      // Use actual event bytes to prove identity.
      const event = TextDelta(index: 0, text: 'relay');
      final deviceBytes = Uint8List.fromList(utf8.encode(encodeEventJson(event)));
      final consumer = _makeConsumer(
        readScript: [deviceBytes, Uint8List(0)],
      );

      final out = BytesIOSink();
      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(outputFormat: Format.structured),
        inputEncoding: 'protobuf',
        outputEncoding: 'json',
        textPrompt: 'x',
        out: out,
      );

      // Output is deviceBytes + '\n' — the device bytes are untouched.
      expect(out.bytes, equals([...deviceBytes, 10]));
    });
  });

  group('relay output — protobuf framing', () {
    test('each read() record emitted with 4-byte big-endian header', () async {
      final script = [
        TextStart(0),
        TextDelta(index: 0, text: 'hello'),
        TextStop(0),
        Complete(_metadata),
      ];
      final rawRecords = script.map(encodeEvent).toList();
      final consumer = _makeConsumer(
        readScript: [...rawRecords, Uint8List(0)],
      );

      final out = BytesIOSink();
      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(outputFormat: Format.structured),
        inputEncoding: 'protobuf',
        outputEncoding: 'protobuf',
        textPrompt: 'hi',
        out: out,
      );

      // Parse the output frames and verify each decodes to the original event.
      final outputBytes = out.bytes;
      var offset = 0;
      final decoded = <ChatEvent>[];
      while (offset + 4 <= outputBytes.length) {
        final len = ByteData.sublistView(outputBytes, offset, offset + 4).getUint32(0);
        offset += 4;
        decoded.add(decodeEvent(outputBytes.sublist(offset, offset + len)));
        offset += len;
      }
      expect(decoded, hasLength(script.length));
      expect(decoded[0], isA<TextStart>());
      expect(decoded[1], isA<TextDelta>());
      expect((decoded[1] as TextDelta).text, 'hello');
      expect(decoded[2], isA<TextStop>());
      expect(decoded[3], isA<Complete>());
    });
  });

  group('relay output — text passthrough (format=text, no framing)', () {
    test('raw bytes reach stdout without framing', () async {
      final textBytes = Uint8List.fromList(utf8.encode('hello world'));
      final consumer = _makeConsumer(
        readScript: [textBytes, Uint8List(0)],
      );

      final out = BytesIOSink();
      // outputFormat=unstructured (text), outputEncoding inert
      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          inputFormat: Format.structured,
          // outputFormat stays unstructured (default)
        ),
        inputEncoding: 'protobuf',
        outputEncoding: 'protobuf', // inert under format=text
        typedStdin: Stream.empty(),
        out: out,
      );

      // No newline, no header — raw passthrough.
      expect(out.bytes, equals(textBytes));
    });
  });

  // ---------------------------------------------------------------------------
  // Encoding ioctl dispatch — verifies that the encoding flags reach the device
  // as CHAT_SET_INPUT_ENCODING (0x0D) / CHAT_SET_OUTPUT_ENCODING (0x0E) ioctls.
  // The relay framing tests above use a scripted device that returns pre-baked
  // bytes regardless of ioctls, so they cannot catch the bug where
  // ioConfig omits encoding from ChatIOConfig (and configToIoctls never fires).
  // ---------------------------------------------------------------------------

  group('encoding ioctl dispatch', () {
    const _chatSetInputEncoding  = 0x0D;
    const _chatSetOutputEncoding = 0x0E;

    test('outputEncoding=json + outputFormat=typed emits CHAT_SET_OUTPUT_ENCODING (0x0E)',
        () async {
      final ioctls = <_IoctlCall>[];
      final consumer = _makeConsumerWithIoctlCapture(
        ioctls: ioctls,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          outputFormat: Format.structured,
          outputEncoding: Encoding.json,
        ),
        inputEncoding: 'protobuf',
        outputEncoding: 'json',
        textPrompt: 'ping',
      );

      final cmds = ioctls.map((c) => c.cmd).toList();
      expect(
        cmds,
        contains(_chatSetOutputEncoding),
        reason: 'CHAT_SET_OUTPUT_ENCODING (0x0E) must be dispatched when '
            'outputEncoding=json; got ioctls: ${cmds.map((c) => '0x${c.toRadixString(16)}').toList()}',
      );
      // Input encoding is default (protobuf) — its ioctl must NOT fire.
      expect(cmds, isNot(contains(_chatSetInputEncoding)));
    });

    test('inputEncoding=json + inputFormat=typed emits CHAT_SET_INPUT_ENCODING (0x0D)',
        () async {
      const msg = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('hi')],
      );
      final jsonLine = encodeMessageJson(msg);
      final inputBytes = Uint8List.fromList(utf8.encode(jsonLine));

      final ioctls = <_IoctlCall>[];
      final consumer = _makeConsumerWithIoctlCapture(
        ioctls: ioctls,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          inputFormat: Format.structured,
          inputEncoding: Encoding.json,
        ),
        inputEncoding: 'json',
        outputEncoding: 'protobuf',
        typedStdin: _streamOf(inputBytes),
      );

      final cmds = ioctls.map((c) => c.cmd).toList();
      expect(
        cmds,
        contains(_chatSetInputEncoding),
        reason: 'CHAT_SET_INPUT_ENCODING (0x0D) must be dispatched when '
            'inputEncoding=json; got: ${cmds.map((c) => '0x${c.toRadixString(16)}').toList()}',
      );
      expect(cmds, isNot(contains(_chatSetOutputEncoding)));
    });

    test('both encodings=json emits both 0x0D and 0x0E', () async {
      // Must use typedStdin — textPrompt forces inputEncoding=protobuf in relayTurn.
      const msg = ChatMessage(
        role: ChatRole.user,
        content: [TextContent('both')],
      );
      final inputBytes =
          Uint8List.fromList(utf8.encode(encodeMessageJson(msg)));

      final ioctls = <_IoctlCall>[];
      final consumer = _makeConsumerWithIoctlCapture(
        ioctls: ioctls,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          inputFormat: Format.structured,
          outputFormat: Format.structured,
          inputEncoding: Encoding.json,
          outputEncoding: Encoding.json,
        ),
        inputEncoding: 'json',
        outputEncoding: 'json',
        typedStdin: _streamOf(inputBytes),
      );

      final cmds = ioctls.map((c) => c.cmd).toList();
      expect(cmds, contains(_chatSetInputEncoding));
      expect(cmds, contains(_chatSetOutputEncoding));
    });

    test('default encodings (protobuf) emit neither 0x0D nor 0x0E', () async {
      final ioctls = <_IoctlCall>[];
      final consumer = _makeConsumerWithIoctlCapture(
        ioctls: ioctls,
        readScript: [Uint8List(0)],
      );

      await consumer.relayTurn(
        config: const ChatIOConfig().copyWith(
          outputFormat: Format.structured,
        ),
        inputEncoding: 'protobuf',
        outputEncoding: 'protobuf',
        textPrompt: 'ping',
      );

      final cmds = ioctls.map((c) => c.cmd).toList();
      expect(cmds, isNot(contains(_chatSetInputEncoding)));
      expect(cmds, isNot(contains(_chatSetOutputEncoding)));
    });
  });

  // ---------------------------------------------------------------------------
  // D2 — function calling: file loading + ioConfig wiring
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

    // ---------------------------------------------------------------------------
    // Encoding ioctl dispatch — this is what the relay tests above do NOT cover:
    // the fake device returns scripted json regardless of which ioctls fire.
    // These tests assert that the IOCTL layer is actually exercised.
    // ---------------------------------------------------------------------------

    test('wiring: functions and functionChoice flow into ChatIOConfig', () {
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
