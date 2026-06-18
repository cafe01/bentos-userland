// OpenAI driver — P4 integration tests, run at the AGGREGATOR (userland).
//
// Migrated from openai-chat-driver/test (S441 turn 2 cycle break): these exercise
// the driver THROUGH the InProcessBentos harness (BentosChatDevice + the full
// open/write/read cycle), so they live where the harness lives. The driver's
// pure white-box request-mapping unit tests stay in the driver package (no
// harness needed there). The driver package no longer references bentos_userland.
//
// ALL tests use apiKey: 'fake' — no OPENAI_API_KEY required, fully keyless.

import 'dart:typed_data';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// P4 helpers
// ---------------------------------------------------------------------------

StreamChannelController<Uint8List> _bindDriver(
  ChatInferenceDriver driver,
) {
  final pair = StreamChannelController<Uint8List>();
  driver.serveChannel(pair.foreign);
  return pair;
}

Future<List<ChatEvent>> _infer(
  StreamChannelController<Uint8List> pair,
  List<ChatMessage> messages, {
  ChatIOConfig config = const ChatIOConfig(),
}) async {
  final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
  final device = BentosChatDevice(bentos, '/dev/llm/openai/gpt-4o');
  return device.infer(messages, config).toList();
}

void main() {
  // -------------------------------------------------------------------------
  // 5. Fake provider — event sequence
  // -------------------------------------------------------------------------

  group('fake provider', () {
    late StreamChannelController<Uint8List> pair;

    setUp(() {
      pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
    });

    test('text cycle: TextStart → TextDelta(s) → TextStop → Complete', () async {
      final events = await _infer(pair, [ChatMessage.userText('hello')]);

      expect(events.first, isA<TextStart>());
      expect(events.whereType<TextDelta>().isNotEmpty, isTrue);
      expect(events.whereType<TextDelta>().map((e) => e.text).join(), contains('hello'));
      expect(events.whereType<TextStop>().isNotEmpty, isTrue);
      expect(events.last, isA<Complete>());
    });

    test('Complete carries EndTurn + TokenUsage', () async {
      final events = await _infer(pair, [ChatMessage.userText('ping')]);
      final complete = events.last as Complete;
      expect(complete.metadata.stopReason, isA<EndTurn>());
      expect(complete.metadata.usage, isNotNull);
      expect(complete.metadata.usage!.inputTokens, greaterThanOrEqualTo(1));
    });

    test('model name is fake-openai-1', () async {
      final events = await _infer(pair, [ChatMessage.userText('x')]);
      expect((events.last as Complete).metadata.model, 'fake-openai-1');
    });
  });

  // -------------------------------------------------------------------------
  // 6. P4 integration
  // -------------------------------------------------------------------------

  group('P4 ioctl config', () {
    late StreamChannelController<Uint8List> pair;

    setUp(() {
      pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
    });

    test('non-default config completes', () async {
      final events = await _infer(
        pair,
        [ChatMessage.userText('tokens')],
        config: const ChatIOConfig(maxTokens: 256),
      );
      expect(events.last, isA<Complete>());
    });

    test('structured input format completes', () async {
      final events = await _infer(
        pair,
        [ChatMessage.userText('structured')],
        config: const ChatIOConfig(inputFormat: Format.structured),
      );
      expect(events.last, isA<Complete>());
    });
  });

  // -------------------------------------------------------------------------
  // 7. Multi-cycle
  // -------------------------------------------------------------------------

  group('multi-cycle', () {
    test('two consecutive infer() calls complete independently', () async {
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/x');

      final e1 = await device.infer([ChatMessage.userText('first')]).toList();
      final e2 = await device.infer([ChatMessage.userText('second')]).toList();

      expect(e1.last, isA<Complete>());
      expect(e2.last, isA<Complete>());
    });
  });

  // -------------------------------------------------------------------------
  // 8. Draining regression — multi-chunk stream must not false-EOF mid-stream
  //    (mirrors the bug caught in the Anthropic driver: _deliverOutput coalesces
  //    all buffered frames; the consumer must see ALL text deltas, not just the
  //    last batch.)
  // -------------------------------------------------------------------------

  group('draining regression', () {
    test('all TextDelta chunks survive multi-chunk fake stream', () async {
      // The fake provider emits 8-char chunks for a long enough reply that
      // P4's coalescing can expose the draining bug if the consumer does not
      // drain every buffered event.
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/multi');

      // Use a long prompt so the fake reply generates several TextDelta chunks.
      const longPrompt = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final events = await device.infer([ChatMessage.userText(longPrompt)]).toList();

      final deltas = events.whereType<TextDelta>().toList();
      final fullText = deltas.map((e) => e.text).join();

      // The fake reply is 'fake: $prompt' — we must reconstruct the entire string.
      expect(fullText, equals('fake: $longPrompt'));
      expect(events.last, isA<Complete>());
    });

    test('two back-to-back infers both deliver complete text (no ghost draining)', () async {
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/drain');

      for (final prompt in ['FIRST_LONG_PROMPT_AAAAAAAAAA', 'SECOND_LONG_PROMPT_BBBBBBBBBB']) {
        final events = await device.infer([ChatMessage.userText(prompt)]).toList();
        final text = events.whereType<TextDelta>().map((e) => e.text).join();
        expect(text, equals('fake: $prompt'), reason: 'prompt: $prompt');
      }
    });
  });

  // -------------------------------------------------------------------------
  // 9. Per-model capabilities
  // -------------------------------------------------------------------------

  group('capabilities', () {
    Future<ChatCapabilities> queryCaps(String model) async {
      final pair = _bindDriver(openaiChatDriver(model: model, apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/$model');
      return device.capabilities;
    }

    test('gpt-4o: 128k context, no reasoning', () async {
      final caps = await queryCaps('gpt-4o');
      expect(caps.maxContextTokens, 128000);
      expect(caps.reasoningSupport, ReasoningSupport.none);
    });

    test('gpt-4o-mini: 128k context, no reasoning', () async {
      final caps = await queryCaps('gpt-4o-mini');
      expect(caps.maxContextTokens, 128000);
      expect(caps.reasoningSupport, ReasoningSupport.none);
    });

    test('o1: 200k context, no reasoning (caller-controlled budget not supported)', () async {
      final caps = await queryCaps('o1');
      expect(caps.maxContextTokens, 200000);
      expect(caps.reasoningSupport, ReasoningSupport.none);
    });

    test('o1-mini: 128k context', () async {
      final caps = await queryCaps('o1-mini');
      expect(caps.maxContextTokens, 128000);
    });

    test('gpt-3.5-turbo: 16k context', () async {
      final caps = await queryCaps('gpt-3.5-turbo');
      expect(caps.maxContextTokens, 16385);
    });

    test('model name is preserved in capabilities', () async {
      final caps = await queryCaps('gpt-4o-mini');
      expect(caps.model, 'gpt-4o-mini');
    });
  });

  // -------------------------------------------------------------------------
  // 10. reasoningBudget guard
  // -------------------------------------------------------------------------

  group('reasoningBudget guard', () {
    test('reasoningBudget > 0 throws DriverError.notSupported', () async {
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/gpt-4o');

      await expectLater(
        device.infer(
          [ChatMessage.userText('think hard')],
          const ChatIOConfig(reasoningBudget: 1000),
        ).toList(),
        throwsA(isA<BentosException>()),
      );
    });

    test('reasoningBudget = 0 does not throw', () async {
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: 'fake'));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});
      final device = BentosChatDevice(bentos, '/dev/llm/openai/gpt-4o');

      final events = await device.infer(
        [ChatMessage.userText('x')],
        const ChatIOConfig(reasoningBudget: 0),
      ).toList();
      expect(events.last, isA<Complete>());
    });
  });

  // -------------------------------------------------------------------------
  // Credential ownership (llm-spec §1) — the key is the DRIVER's, resolved at
  // open. Absent → the device's open fails with EACCES, surfaced to the
  // consumer as a BentosException. No network: an empty apiKey forces the
  // missing-key path deterministically regardless of the test process env.
  // -------------------------------------------------------------------------
  group('credential ownership', () {
    test('missing key fails open with EACCES, not a boot crash', () async {
      final pair = _bindDriver(openaiChatDriver(model: 'gpt-4o', apiKey: ''));
      final bentos = InProcessBentos(capMap: {'/dev/llm/': pair.local});

      await expectLater(
        bentos.open('/dev/llm/openai/gpt-4o'),
        throwsA(isA<BentosException>()
            .having((e) => e.errno, 'errno', BentosErrno.eacces)),
      );
    });
  });
}
