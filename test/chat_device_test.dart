/// BentosChatDevice's data path against the SDK's real L1 machinery: message
/// frames must arrive as canonical protobuf the subsystem codec decodes, and
/// the event frames the driver emits must come back as typed ChatEvents,
/// the stream ending at Complete. (The full P4 driver is D3 territory; this
/// asserts the binding's half of the contract.)
library;

import 'dart:typed_data';

// hide: the SDK still exports its pre-ChatInference inference types (M16/M17
// leftovers, superseded by chat_inference) — cleanup queued with D3.
import 'package:bentos_driver_sdk/bentos_driver_sdk.dart'
    hide TextDelta, TokenUsage;
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:fixnum/fixnum.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  test('infer(): writes message frames, streams typed events until Complete',
      () async {
    final received = <ChatMessage>[];
    final script = <ChatEvent>[
      const TextStart(0),
      const TextDelta(index: 0, text: 'Hello, '),
      const TextDelta(index: 0, text: 'BentOS.'),
      const TextStop(0),
      Complete(ChatMetadata(
        model: 'scripted-1',
        stopReason: const EndTurn(),
        usage: const TokenUsage(inputTokens: 3, outputTokens: 4),
      )),
    ];
    var cursor = 0;

    final driver = BentosDriver(
      onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
      onWrite: (req, ctx) {
        // The binding's frames must be decodable by the subsystem codec.
        received.add(decodeMessage(req.data));
        return FuseResponse(write: WriteReply(count: Int64(req.data.length)));
      },
      onRead: (req, ctx) => FuseResponse(
        buf: BufReply(
          data: cursor < script.length
              ? encodeEvent(script[cursor++])
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
      '/dev/llm/anthropic/claude-haiku-4-5',
    );

    final events =
        await device.infer([ChatMessage.userText('hi')]).toList();

    expect(received, [ChatMessage.userText('hi')]);
    expect(events, script); // typed equality, Complete-terminated
    expect(cursor, script.length);
  });

  test('non-default config is refused until the ConfigCodec lands (D3)', () {
    final pair = StreamChannelController<Uint8List>();
    BentosDriver(onOpen: (req, ctx) => FuseResponse(open: OpenReply()))
        .serveChannel(pair.foreign);
    final device = BentosChatDevice(
      InProcessBentos(capMap: {'/dev/llm/': pair.local}),
      '/dev/llm/x',
    );
    expect(
      () => device
          .infer([ChatMessage.userText('hi')], ChatIOConfig(maxTokens: 5))
          .toList(),
      throwsUnsupportedError,
    );
  });
}
