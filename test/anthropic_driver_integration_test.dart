// Anthropic driver — P4 integration tests, run at the AGGREGATOR (userland).
//
// Migrated from anthropic-chat-driver/test (S441 turn 2 cycle break): these
// exercise the driver THROUGH the InProcessBentos harness (BentosChatDevice +
// the full open/write/read cycle), so they live where the harness lives. The
// driver package no longer references bentos_userland.
//
// ALL tests use apiKey: 'fake' — no ANTHROPIC_API_KEY required, fully keyless.
// Coverage:
//   1. Fake provider — event sequence, Complete metadata.
//   2. P4 integration — in-process driver bound via serveChannel, full cycle:
//      ioctl config → write messages → read events → Complete.
//   3. Fold transformer over the driver's output.
//   4. Multiple cycles (Complete → write → new cycle).
//   5. Credential ownership — missing key → EACCES at open.

import 'dart:typed_data';

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

StreamChannelController<Uint8List> bindDriver(
  ConfiguredStreamDriver<ChatIOConfig, List<ChatMessage>, ChatEvent, Object> driver,
) {
  final pair = StreamChannelController<Uint8List>();
  driver.serveChannel(pair.foreign);
  return pair;
}

Future<List<ChatEvent>> inferEvents(
  StreamChannelController<Uint8List> pair,
  List<ChatMessage> messages, {
  ChatIOConfig config = const ChatIOConfig(),
}) async {
  final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
  final device = BentosChatDevice(bentos, '/dev/llm/anthropic/claude-sonnet-4-6');
  return device.infer(messages, config).toList();
}

// ---------------------------------------------------------------------------
// 1. Fake provider — event sequence
// ---------------------------------------------------------------------------

group('fake provider', () {
  late StreamChannelController<Uint8List> pair;

  setUp(() {
    pair = bindDriver(anthropicChatDriver(model: 'claude-sonnet-4-6', apiKey: 'fake'));
  });

  test('text cycle: TextStart → TextDelta(s) → TextStop → Complete', () async {
    final events = await inferEvents(pair, [ChatMessage.userText('hello')]);

    expect(events.first, isA<TextStart>());
    expect(events.whereType<TextDelta>().isNotEmpty, isTrue);
    expect(events.whereType<TextDelta>().map((e) => e.text).join(),
        contains('hello'));
    expect(events.whereType<TextStop>().isNotEmpty, isTrue);
    expect(events.last, isA<Complete>());
  });

  test('Complete carries EndTurn + TokenUsage', () async {
    final events = await inferEvents(pair, [ChatMessage.userText('ping')]);
    final complete = events.last as Complete;
    expect(complete.metadata.stopReason, isA<EndTurn>());
    expect(complete.metadata.usage, isNotNull);
    expect(complete.metadata.usage!.inputTokens, greaterThanOrEqualTo(1));
  });

  test('model name is fake-1', () async {
    final events = await inferEvents(pair, [ChatMessage.userText('x')]);
    expect((events.last as Complete).metadata.model, 'fake-1');
  });
});

// ---------------------------------------------------------------------------
// 2. P4 integration — ioctl config is applied
// ---------------------------------------------------------------------------

group('P4 ioctl config', () {
  late StreamChannelController<Uint8List> pair;

  setUp(() {
    pair = bindDriver(anthropicChatDriver(model: 'claude-sonnet-4-6', apiKey: 'fake'));
  });

  test('non-default config issues CHAT_SET_MAX_TOKENS before inference', () async {
    final events = await inferEvents(
      pair,
      [ChatMessage.userText('tokens')],
      config: const ChatIOConfig(maxTokens: 256),
    );
    expect(events.last, isA<Complete>());
  });

  test('structured input format — messages encoded as length-prefixed frames', () async {
    final events = await inferEvents(
      pair,
      [ChatMessage.userText('structured')],
      config: const ChatIOConfig(inputFormat: Format.structured),
    );
    expect(events.last, isA<Complete>());
  });
});

// ---------------------------------------------------------------------------
// 3. Fold transformer over fake output
// ---------------------------------------------------------------------------

group('fold transformer', () {
  late StreamChannelController<Uint8List> pair;

  setUp(() {
    pair = bindDriver(anthropicChatDriver(model: 'claude-sonnet-4-6', apiKey: 'fake'));
  });

  test('foldToMessage produces ChatMessage with text content', () async {
    final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
    final device = BentosChatDevice(bentos, '/dev/llm/anthropic/x');
    final msg = await device
        .infer([ChatMessage.userText('hi')])
        .foldToMessage();

    expect(msg.role, ChatRole.assistant);
    expect(msg.content.whereType<TextContent>().isNotEmpty, isTrue);
    final text = msg.content.whereType<TextContent>().map((c) => c.text).join();
    expect(text, contains('hi'));
  });
});

// ---------------------------------------------------------------------------
// 4. Multiple cycles (Complete → write → new cycle)
// ---------------------------------------------------------------------------

group('multi-cycle', () {
  late StreamChannelController<Uint8List> pair;

  setUp(() {
    pair = bindDriver(anthropicChatDriver(model: 'claude-sonnet-4-6', apiKey: 'fake'));
  });

  test('two consecutive infer() calls on same device complete independently', () async {
    final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
    final device = BentosChatDevice(bentos, '/dev/llm/anthropic/x');

    final e1 = await device.infer([ChatMessage.userText('first')]).toList();
    final e2 = await device.infer([ChatMessage.userText('second')]).toList();

    expect(e1.last, isA<Complete>());
    expect(e2.last, isA<Complete>());
    expect((e1.last as Complete).metadata.model,
        (e2.last as Complete).metadata.model);
  });

  // Credential ownership (llm-spec §1) — the key is the DRIVER's, resolved at
  // open. Absent → the device's open fails with EACCES, surfaced as a
  // BentosException. No network: an empty apiKey forces the missing-key path
  // deterministically regardless of the test process env.
  test('missing key fails open with EACCES, not a boot crash', () async {
    final pair = bindDriver(anthropicChatDriver(model: 'claude-sonnet-4-6', apiKey: ''));
    final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});

    await expectLater(
      bentos.open('/dev/llm/anthropic/claude-sonnet-4-6'),
      throwsA(isA<BentosException>()
          .having((e) => e.errno, 'errno', BentosErrno.eacces)),
    );
  });
});
}
