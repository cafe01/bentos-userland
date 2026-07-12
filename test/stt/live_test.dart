import 'dart:convert' as dc;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_userland/boot_stt.dart';
import 'package:bentos_userland/stt.dart';
import 'package:openai_live_stt_driver/openai_live_stt_driver.dart';
import 'package:stt_inference/stt_inference.dart';
import 'package:test/test.dart';

// A few bytes per chunk — content is inert for the fake provider, which emits
// one growing partial per chunk regardless of the payload.
Uint8List pcmChunk(int seed) => Uint8List.fromList([seed, seed + 1, seed + 2]);

TranscriptSegment seg(int index, String text) =>
    TranscriptSegment(index: index, text: text, startMs: 0, endMs: 100);

// Captures text/bytes written to an injected IOSink.
class BytesIOSink implements IOSink {
  final _bytes = BytesBuilder();

  String get text => dc.utf8.decode(_bytes.toBytes());

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
  void writeCharCode(int charCode) => _bytes.add([charCode]);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.add(chunk);
    }
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

void main() {
  group('runLive (fake driver)', () {
    test('committed finals only reach stdout; partials are dropped', () async {
      // Default fake: one growing partial per chunk (live, before drain), then
      // one committed final at feed close. The face keeps the final only.
      final driver = openaiLiveSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runLive(
        driver,
        audioIn: Stream.fromIterable([pcmChunk(0), pcmChunk(3)]),
        out: out,
        err: err,
      );

      // Two chunks fed → the final commits 'hyp-2'; the two partials vanish.
      expect(out.text, 'hyp-2\n');
      expect(err.text, isEmpty);
    });

    test('partials and corrections are both dropped; each final is a line',
        () async {
      // A scripted session with the full §4.3 union: a volatile partial, a
      // committed final, a whole-utterance correction of it, a second final.
      // The casual register emits the two finals, one per line, and neither
      // rewrites nor leaks the hypothesis.
      final driver = openaiLiveSttDriver(
        model: 'whisper-1',
        apiKey: 'fake',
        fakeScript: [
          const Partial(index: 0, text: 'volatile-hyp'),
          LiveFinal(index: 0, segment: seg(0, 'first')),
          Correction(index: 0, segment: seg(0, 'REWRITTEN')),
          LiveFinal(index: 1, segment: seg(1, 'second')),
          const LiveComplete(
            RunMetadata(model: 'fake-realtime-1', audioDurationMs: 200, timingMs: 1),
          ),
        ],
      );
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runLive(
        driver,
        audioIn: Stream.value(pcmChunk(0)),
        out: out,
        err: err,
      );

      expect(out.text, 'first\nsecond\n');
      expect(err.text, isEmpty);
    });

    test('-v surfaces run metadata on stderr, off the text seam', () async {
      final driver = openaiLiveSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runLive(
        driver,
        audioIn: Stream.value(pcmChunk(0)),
        out: out,
        err: err,
        verbose: true,
      );

      expect(out.text, 'hyp-1\n');
      expect(err.text, contains('fake-realtime-1'));
    });

    test('an empty session is legitimate — immediate EOF, no output', () async {
      // §2.3: a session with no writes drains straight to COMPLETE. The live
      // face is NOT the transcribe face — empty is not EINVAL here.
      final driver = openaiLiveSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();

      await runLive(driver, audioIn: const Stream.empty(), out: out);

      expect(out.text, isEmpty);
    });
  });

  group('negotiateLiveTriple (§3.3 — default read from the table)', () {
    LiveTranscriptionInfo info(List<int> rates) => LiveTranscriptionInfo(
          model: 'm',
          pcmRates: rates,
          pcmEncodings: const ['s16le'],
          maxChannels: 1,
          languages: const [],
          maxSessionMs: 0,
        );

    test('canonical offered, no --rate → 16 kHz flag-free', () {
      final t = negotiateLiveTriple(info(const [16000, 24000]));
      expect(t.rate, 16000);
      expect(t.encoding, PcmEncoding.s16le);
      expect(t.channels, 1);
    });

    test('single non-canonical rate, no --rate → the device speaks for itself',
        () {
      // OpenAI Realtime: 24 kHz-only. The face adopts the sworn rate, no flag.
      expect(negotiateLiveTriple(info(const [24000])).rate, 24000);
    });

    test('several rates, none canonical, no --rate → ambiguous, refuse', () {
      expect(
        () => negotiateLiveTriple(info(const [24000, 48000])),
        throwsA(isA<SttFormatError>()
            .having((e) => e.rates, 'rates', const [24000, 48000])),
      );
    });

    test('explicit --rate overrides the default; validation is the ioctl\'s',
        () {
      // Even a rate outside the table passes here — negotiate only proposes;
      // STT_SET_PCM_FORMAT is where the table says yes or no.
      expect(negotiateLiveTriple(info(const [16000]), rate: 24000).rate, 24000);
    });
  });

  group('runLive — format negotiation over the fake driver', () {
    test('an unsupported --rate override surfaces a teaching SttFormatError',
        () async {
      // The fake table is 16 kHz-only; asserting 48 kHz is rejected at
      // STT_SET_PCM_FORMAT and the face names the accepted rate.
      final driver = openaiLiveSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();

      expect(
        () => runLive(
          driver,
          audioIn: Stream.value(pcmChunk(0)),
          out: out,
          rate: 48000,
        ),
        throwsA(isA<SttFormatError>()
            .having((e) => e.rates, 'rates', const [16000])),
      );
    });

    test('the canonical default still runs flag-free over the fake', () async {
      // Regression: negotiation + STT_SET_PCM_FORMAT(16k) must not perturb the
      // flag-free happy path the fake's 16 kHz table already honors.
      final driver = openaiLiveSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();

      await runLive(
        driver,
        audioIn: Stream.value(pcmChunk(0)),
        out: out,
      );

      expect(out.text, 'hyp-1\n');
    });
  });

  group('bootLiveDevice (routing)', () {
    setUp(() {
      clearSttDrivers();
      registerLiveDriver(
        'openai',
        (model) => openaiLiveSttDriver(model: model, apiKey: 'fake'),
      );
    });

    test('routes /dev/stt/<vendor>/<model>/live to the driver', () {
      final driver = bootLiveDevice('/dev/stt/openai/whisper-1/live');
      expect(driver, isA<LiveTranscriptionDriver>());
    });

    test('the transcribe protocol segment is not a live device', () {
      expect(
        () => bootLiveDevice('/dev/stt/openai/whisper-1/transcribe'),
        throwsA(isA<SttBootException>()),
      );
    });

    test('a path without the protocol segment is a routing error', () {
      expect(
        () => bootLiveDevice('/dev/stt/openai/whisper-1'),
        throwsA(isA<SttBootException>()),
      );
    });

    test('an unregistered vendor is a routing error', () {
      expect(
        () => bootLiveDevice('/dev/stt/acme/whisper-1/live'),
        throwsA(isA<SttBootException>()),
      );
    });
  });
}
