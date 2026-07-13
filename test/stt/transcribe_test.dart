import 'dart:async';
import 'dart:convert' as dc;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_userland/boot_stt.dart';
import 'package:bentos_userland/stt.dart';
import 'package:openai_stt_driver/openai_stt_driver.dart';
import 'package:stt_inference/stt_inference.dart';
import 'package:test/test.dart';

// A minimal WAV-signatured buffer — 'RIFF'....'WAVE' — so the base sniffs
// container=wav (fake table carries wav). Content beyond the signature is
// inert for the fake provider.
Uint8List wavBytes() {
  final b = BytesBuilder();
  b.add(dc.ascii.encode('RIFF'));
  b.add(const [0, 0, 0, 0]); // chunk size (ignored by the fake)
  b.add(dc.ascii.encode('WAVE'));
  b.add(dc.ascii.encode('fake pcm payload'));
  return b.toBytes();
}

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
  group('runTranscribe (fake driver)', () {
    test('audio in → transcript on stdout (the echo-equivalent)', () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runTranscribe(
        driver,
        audioIn: Stream.value(wavBytes()),
        out: out,
        err: err,
      );

      // Casual register: committed segment text only, trailing newline.
      expect(out.text, 'hello\n');
      // Complete metadata is dropped from the text seam.
      expect(err.text, isEmpty);
    });

    test('-v surfaces run metadata on stderr, off the text seam', () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();
      final err = BytesIOSink();

      await runTranscribe(
        driver,
        audioIn: Stream.value(wavBytes()),
        out: out,
        err: err,
        feedbackEnabled: true,
      );

      expect(out.text, 'hello\n');
      expect(err.text, contains('fake-whisper-1'));
    });

    test('empty audio fails the job (§2.1 — EINVAL, not a silent empty run)',
        () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();

      expect(
        () => runTranscribe(
          driver,
          audioIn: const Stream.empty(),
          out: out,
        ),
        throwsA(isA<DriverError>()),
      );
    });
  });

  group('bootTranscribeDevice (routing)', () {
    setUp(() {
      clearSttDrivers();
      registerTranscribeDriver(
        'openai',
        (model) => openaiSttDriver(model: model, apiKey: 'fake'),
      );
    });

    test('routes /dev/stt/<vendor>/<model>/transcribe to the driver', () {
      final driver =
          bootTranscribeDevice('/dev/stt/openai/whisper-1/transcribe');
      expect(driver, isA<TranscriptionDriver>());
    });

    test('a path without the protocol segment is a routing error', () {
      expect(
        () => bootTranscribeDevice('/dev/stt/openai/whisper-1'),
        throwsA(isA<SttBootException>()),
      );
    });

    test('an unregistered vendor is a routing error', () {
      expect(
        () => bootTranscribeDevice('/dev/stt/acme/whisper-1/transcribe'),
        throwsA(isA<SttBootException>()),
      );
    });
  });

  group('resolveSttDevice (precedence)', () {
    test('explicit short form normalises to a /dev/stt base', () {
      expect(
        resolveSttDevice('openai/whisper-1'),
        '/dev/stt/openai/whisper-1',
      );
    });

    test('env overrides the default, explicit overrides env', () {
      const env = {sttDeviceEnvVar: 'openai/env-model'};
      expect(resolveSttDevice(null, environment: env),
          '/dev/stt/openai/env-model');
      expect(resolveSttDevice('openai/flag-model', environment: env),
          '/dev/stt/openai/flag-model');
      expect(resolveSttDevice(null), defaultSttDevice);
    });

    test('withVerb appends the protocol segment', () {
      expect(withVerb('/dev/stt/openai/whisper-1', 'transcribe'),
          '/dev/stt/openai/whisper-1/transcribe');
    });
  });
}
