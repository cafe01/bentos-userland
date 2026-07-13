import 'dart:async';
import 'dart:convert' as dc;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_userland/stt.dart';
import 'package:openai_stt_driver/openai_stt_driver.dart';
import 'package:test/test.dart';

// A minimal WAV-signatured buffer — same fixture as transcribe_test.dart.
Uint8List wavBytes() {
  final b = BytesBuilder();
  b.add(dc.ascii.encode('RIFF'));
  b.add(const [0, 0, 0, 0]);
  b.add(dc.ascii.encode('WAVE'));
  b.add(dc.ascii.encode('fake pcm payload'));
  return b.toBytes();
}

// Captures text written to an injected IOSink.
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
  group('resolveSttInput (§5.4-3 — the stdin binary guard, no interactive read)', () {
    test('transcribe: stdin terminal → refused with the §3.3 message', () {
      final resolution = resolveSttInput(SttInputKind.transcribe,
          stdinIsTerminal: true);
      expect(resolution, isA<SttInputRefused>());
      expect(
        (resolution as SttInputRefused).message,
        'stt: no audio on the terminal — pass a file (stt recording.wav) or '
        'pipe one',
      );
    });

    test('live: stdin terminal → refused with the §3.4 message', () {
      final resolution =
          resolveSttInput(SttInputKind.live, stdinIsTerminal: true);
      expect(resolution, isA<SttInputRefused>());
      expect(
        (resolution as SttInputRefused).message,
        'stt: no audio on the terminal — pipe a live PCM source',
      );
    });

    test('transcribe: stdin piped → allowed (the working pipe case)', () {
      final resolution = resolveSttInput(SttInputKind.transcribe,
          stdinIsTerminal: false);
      expect(resolution, isA<SttInputAllowed>());
    });

    test('live: stdin piped → allowed', () {
      final resolution =
          resolveSttInput(SttInputKind.live, stdinIsTerminal: false);
      expect(resolution, isA<SttInputAllowed>());
    });
  });

  group('stt transcribe still works when stdin is a pipe (end-to-end)', () {
    test('allowed stdin still transcribes to the out sink', () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final out = BytesIOSink();

      await runTranscribe(
        driver,
        audioIn: Stream.value(wavBytes()),
        out: out,
      );

      expect(out.text, isNotEmpty);
    });
  });

  group('sttFeedbackEnabled (§5.4-6 — the three-way gate, identical to '
      "tts's", () {
    test('quiet wins even at a terminal with verbose set', () {
      expect(
        sttFeedbackEnabled(
            stderrIsTerminal: true, verbose: true, quiet: true),
        isFalse,
      );
    });

    test('terminal, no flags → on', () {
      expect(
        sttFeedbackEnabled(
            stderrIsTerminal: true, verbose: false, quiet: false),
        isTrue,
      );
    });

    test('pipe, no flags → off', () {
      expect(
        sttFeedbackEnabled(
            stderrIsTerminal: false, verbose: false, quiet: false),
        isFalse,
      );
    });

    test('pipe + verbose → forced on', () {
      expect(
        sttFeedbackEnabled(
            stderrIsTerminal: false, verbose: true, quiet: false),
        isTrue,
      );
    });
  });

  group('the three beats — pure line formatters', () {
    test('intent: source → stdout, language omitted when unset', () {
      expect(sttIntentLine(source: 'audio'), 'stt: audio → stdout');
    });

    test('intent: language appended when requested', () {
      expect(
        sttIntentLine(source: 'audio', language: 'pt'),
        'stt: audio → stdout · language pt',
      );
    });

    test('intent: live carries a format aside (requested rate)', () {
      expect(
        sttIntentLine(source: 'live audio', format: '16000Hz'),
        'stt: live audio → stdout · 16000Hz',
      );
    });

    test('resolved: model only, language echoed when requested', () {
      expect(sttResolvedLine(model: 'whisper-1'), 'stt: whisper-1');
      expect(
        sttResolvedLine(model: 'whisper-1', language: 'pt'),
        'stt: whisper-1 · pt',
      );
    });

    test('completion: words · wall-clock', () {
      expect(
        sttCompletionLine(words: 12, elapsed: const Duration(milliseconds: 7)),
        'stt: 12 words · 7ms',
      );
    });
  });

  group('stt transcribe feedback channel (end-to-end)', () {
    test('feedbackEnabled: false → err sink stays empty', () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final err = BytesIOSink();

      await runTranscribe(
        driver,
        audioIn: Stream.value(wavBytes()),
        out: BytesIOSink(),
        err: err,
      );

      expect(err.text, isEmpty);
    });

    test('feedbackEnabled: true → resolved + completion beats land on err, '
        'never on out', () async {
      final driver = openaiSttDriver(model: 'whisper-1', apiKey: 'fake');
      final err = BytesIOSink();
      final out = BytesIOSink();

      await runTranscribe(
        driver,
        audioIn: Stream.value(wavBytes()),
        out: out,
        err: err,
        feedbackEnabled: true,
      );

      expect(err.text, contains('fake-whisper-1'));
      expect(err.text, contains('words'));
      expect(out.text, isNot(contains('fake-whisper-1')));
    });
  });
}
