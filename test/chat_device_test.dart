/// BentosChatDevice's data path against the SDK's real L1 machinery: message
/// frames must arrive as canonical protobuf the subsystem codec decodes, and
/// the event frames the driver emits must come back as typed ChatEvents,
/// the stream ending at Complete. (The full P4 driver is D3 territory; this
/// asserts the binding's half of the contract.)
library;

import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat_inference/chat_inference.dart';
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
      '/dev/llm/anthropic/claude-haiku-4-5',
    );

    final events =
        await device.infer([ChatMessage.userText('hi')]).toList();

    expect(received, [ChatMessage.userText('hi')]);
    expect(events, script); // typed equality, Complete-terminated
    expect(cursor, script.length);
  });

  test('non-default config issues CHAT_SET_* ioctls before write', () async {
    final ioctls = <(int, Uint8List)>[];
    final script = <ChatEvent>[
      Complete(ChatMetadata(model: 'm', stopReason: const EndTurn())),
    ];
    var cursor = 0;

    final driver = BentosDriver(
      onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
      onIoctl: (req, ctx) {
        ioctls.add((req.cmd, Uint8List.fromList(req.inBuf)));
        return FuseResponse(ioctl: IoctlReply());
      },
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
      '/dev/llm/x',
    );

    await device
        .infer(
          [ChatMessage.userText('hi')],
          const ChatIOConfig(maxTokens: 256, temperature: 0.7),
        )
        .toList();

    expect(ioctls.map((o) => o.$1), containsAll([0x01, 0x02]));
    final maxTok = ioctls.firstWhere((o) => o.$1 == 0x01);
    expect(decodeIoctlInt32(maxTok.$2), equals(256));
    final temp = ioctls.firstWhere((o) => o.$1 == 0x02);
    expect(decodeIoctlDouble(temp.$2), closeTo(0.7, 1e-9));
  });
}
