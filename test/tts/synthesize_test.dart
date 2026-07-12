import 'dart:async';
import 'dart:convert' as dc;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart' show DriverError;
import 'package:bentos_userland/boot_tts.dart';
import 'package:bentos_userland/tts.dart';
import 'package:openai_tts_driver/openai_tts_driver.dart';
import 'package:tts_inference/tts_inference.dart';
import 'package:test/test.dart';

// Captures bytes written to an injected IOSink — both raw (audio) and decoded
// (stderr text).
class BytesIOSink implements IOSink {
  final _bytes = BytesBuilder();

  Uint8List get bytes => _bytes.toBytes();
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
  group('runSynthesize (fake driver)', () {
    test('text in → audio bytes on stdout, streaming-WAV framed', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hello world')),
        out: out,
        err: err,
      );

      // The base frames WAV: a 44-byte streaming header (length fields
      // 0xFFFFFFFF) rides the first chunk, then the payload bytes.
      final b = out.bytes;
      expect(dc.ascii.decode(b.sublist(0, 4)), 'RIFF');
      expect(dc.ascii.decode(b.sublist(8, 12)), 'WAVE');
      expect(b.length, 44 + 8); // header + the two fake payload chunks
      expect(b.sublist(44), [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]);
      // No typed register (§4.4): nothing leaks to stderr without -v.
      expect(err.text, isEmpty);
    });

    test('-v surfaces run metadata on stderr, off the audio seam', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hello')),
        out: out,
        err: err,
        verbose: true,
      );

      expect(out.bytes.length, greaterThan(44)); // audio still flows
      expect(err.text, contains('fake-tts-1'));
      expect(err.text, contains('wav'));
    });

    test('multibyte text split across stdin chunks is not corrupted',
        () async {
      final probe = SynthesizeProbe();
      final driver =
          openaiTtsDriver(model: 'tts-1', apiKey: 'fake', fakeProbe: probe);
      final out = BytesIOSink();

      // 'é' is 0xC3 0xA9 — split the two bytes across two stdin chunks; the
      // streaming decoder must buffer the partial sequence, not corrupt it.
      await runSynthesize(
        driver,
        textIn: Stream.fromIterable([
          [0x63, 0xC3], // 'c' + first byte of 'é'
          [0xA9], // second byte of 'é'
        ]),
        out: out,
      );

      expect(probe.lastText, 'cé');
    });

    test('pcm opt-in is headerless — raw bytes, no WAV frame (§3.4)', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final out = BytesIOSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hi')),
        out: out,
        format: const PcmOutput(
          PcmTriple(rate: 24000, encoding: PcmEncoding.s16le, channels: 1),
        ),
      );

      // No 44-byte header: the two fake chunks verbatim.
      expect(out.bytes,
          [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]);
    });

    test('a voice outside the table is a TtsFormatError, not a bare DriverError',
        () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');

      expect(
        () => runSynthesize(
          driver,
          textIn: Stream.value(dc.utf8.encode('hi')),
          out: BytesIOSink(),
          voice: 'not-a-real-voice',
        ),
        throwsA(isA<TtsFormatError>()),
      );
    });

    test('speed outside the range is a TtsFormatError', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');

      expect(
        () => runSynthesize(
          driver,
          textIn: Stream.value(dc.utf8.encode('hi')),
          out: BytesIOSink(),
          speed: 99.0, // fake range is 0.25–4.0
        ),
        throwsA(isA<TtsFormatError>()),
      );
    });

    test('a settled voice is accepted and the job runs (probe sees the text)',
        () async {
      final probe = SynthesizeProbe();
      final driver =
          openaiTtsDriver(model: 'tts-1', apiKey: 'fake', fakeProbe: probe);
      final out = BytesIOSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hi')),
        out: out,
        voice: 'voice-1', // the sole fake voice
        speed: 1.5,
      );

      expect(probe.lastText, 'hi');
      expect(out.bytes.length, greaterThan(44));
    });

    test('empty text fails the job (§2.1 — EINVAL, not a silent empty run)',
        () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final out = BytesIOSink();

      expect(
        () => runSynthesize(
          driver,
          textIn: const Stream.empty(),
          out: out,
        ),
        throwsA(isA<DriverError>()),
      );
    });
  });

  group('bootTtsDevice (routing)', () {
    setUp(() {
      clearTtsDrivers();
      registerTtsDriver(
        'openai',
        (model) => openaiTtsDriver(model: model, apiKey: 'fake'),
      );
    });

    test('routes /dev/tts/<vendor>/<model> to the driver', () {
      final driver = bootTtsDevice('/dev/tts/openai/tts-1');
      expect(driver, isA<SpeechSynthesisDriver>());
    });

    test('a malformed path is a routing error', () {
      expect(
        () => bootTtsDevice('/dev/tts/openai'),
        throwsA(isA<TtsBootException>()),
      );
    });

    test('an unregistered vendor is a routing error', () {
      expect(
        () => bootTtsDevice('/dev/tts/acme/tts-1'),
        throwsA(isA<TtsBootException>()),
      );
    });
  });

  group('resolveTtsDevice (precedence)', () {
    test('explicit short form normalises to a /dev/tts path', () {
      expect(resolveTtsDevice('openai/tts-1'), '/dev/tts/openai/tts-1');
    });

    test('env overrides the default, explicit overrides env', () {
      const env = {ttsDeviceEnvVar: 'openai/env-model'};
      expect(resolveTtsDevice(null, environment: env),
          '/dev/tts/openai/env-model');
      expect(resolveTtsDevice('openai/flag-model', environment: env),
          '/dev/tts/openai/flag-model');
      expect(resolveTtsDevice(null), defaultTtsDevice);
    });
  });
}
