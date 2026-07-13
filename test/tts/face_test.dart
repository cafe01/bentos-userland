import 'dart:async';
import 'dart:convert' as dc;
import 'dart:io';
import 'dart:typed_data';

import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:bentos_userland/src/tts/sink.dart';
import 'package:bentos_userland/src/tts/text_source.dart';
import 'package:bentos_userland/src/tts/wav_length_patch.dart';
import 'package:bentos_userland/tts.dart';
import 'package:openai_tts_driver/openai_tts_driver.dart';
import 'package:test/test.dart';
import 'package:tts_inference/tts_inference.dart';

List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];

// A synthetic streaming-WAV header (§3.4): RIFF/data sizes both the
// 0xFFFFFFFF sentinel, an arbitrary-size fmt chunk in between (odd sizes
// exercise the RIFF even-padding rule).
List<int> _streamingWavHeader({int fmtChunkSize = 16}) {
  final b = BytesBuilder();
  b.add(dc.ascii.encode('RIFF'));
  b.add(const [0xff, 0xff, 0xff, 0xff]); // RIFF ChunkSize sentinel
  b.add(dc.ascii.encode('WAVE'));
  b.add(dc.ascii.encode('fmt '));
  b.add(_u32le(fmtChunkSize));
  b.add(List.filled(fmtChunkSize, 0));
  if (fmtChunkSize.isOdd) b.add(const [0]); // chunk padding, not counted in size
  b.add(dc.ascii.encode('data'));
  b.add(const [0xff, 0xff, 0xff, 0xff]); // data ChunkSize sentinel
  return b.toBytes();
}

void main() {
  group('resolveTtsTextSource (§5.4-3 — the tts input-precedence law)', () {
    test('positional present → wins, regardless of stdin', () {
      final resolution =
          resolveTtsTextSource('hello world', stdinIsTerminal: true);
      expect(resolution, isA<TtsTextSourcePositional>());
      expect((resolution as TtsTextSourcePositional).text, 'hello world');
    });

    test('positional present + stdin piped → positional still wins '
        '(precedence, not a race)', () {
      final resolution =
          resolveTtsTextSource('hello world', stdinIsTerminal: false);
      expect(resolution, isA<TtsTextSourcePositional>());
    });

    test('no positional + stdin piped → the pipe shape', () {
      final resolution = resolveTtsTextSource(null, stdinIsTerminal: false);
      expect(resolution, isA<TtsTextSourceStdin>());
    });

    test('no positional + stdin a terminal → interactive keyboard read', () {
      final resolution = resolveTtsTextSource(null, stdinIsTerminal: true);
      expect(resolution, isA<TtsTextSourceInteractive>());
    });
  });

  group('readInteractiveText — the keyboard-to-EOF collector', () {
    test('accumulates keystrokes across chunks into one string', () async {
      final keystrokes = Stream<List<int>>.fromIterable([
        dc.utf8.encode('hello '),
        dc.utf8.encode('world'),
      ]);
      final text = await readInteractiveText(keystrokes);
      expect(text, 'hello world');
    });

    test('immediate Ctrl-D (empty stream) → empty string, no crash', () async {
      final text = await readInteractiveText(const Stream<List<int>>.empty());
      expect(text, isEmpty);
    });
  });

  group('bare `tts` routing (product-spec fork #10 — never a usage dump)',
      () {
    test('the default-verb prepend fires for a truly bare invocation', () {
      expect(withDefaultVerb([], {'synthesize'}), ['synthesize']);
    });

    test('--version is left untouched, never routed to synthesize', () {
      expect(withDefaultVerb(['--version'], {'synthesize'}),
          ['--version']);
    });

    test('--help is left untouched', () {
      expect(withDefaultVerb(['--help'], {'synthesize'}), ['--help']);
    });

    test('an explicit known verb is left untouched', () {
      expect(withDefaultVerb(['synthesize', '-v'], {'synthesize'}),
          ['synthesize', '-v']);
    });

    test('a bare positional (no verb) is routed to synthesize', () {
      expect(withDefaultVerb(['hello world'], {'synthesize'}),
          ['synthesize', 'hello world']);
    });
  });

  group('resolveTtsSink (§5.4-4 — the stdout binary guard)', () {
    test('no -o + stdout terminal → refused before any device is touched',
        () {
      final resolution = resolveTtsSink(null, stdoutIsTerminal: true);
      expect(resolution, isA<TtsSinkRefused>());
      expect((resolution as TtsSinkRefused).message,
          contains('refusing to write audio to a terminal'));
    });

    test('no -o + stdout piped → resolves to stdout (the working pipe case)',
        () {
      final resolution = resolveTtsSink(null, stdoutIsTerminal: false);
      expect(resolution, isA<TtsSinkResolved>());
      expect((resolution as TtsSinkResolved).file, isNull);
    });

    test('-o <file> → resolves to that file, regardless of stdout terminal',
        () {
      final resolution =
          resolveTtsSink('hi.wav', stdoutIsTerminal: true);
      expect(resolution, isA<TtsSinkResolved>());
      expect((resolution as TtsSinkResolved).file!.path, 'hi.wav');
    });

    test('-o - forces stdout, bypassing the guard even at a terminal', () {
      final resolution = resolveTtsSink('-', stdoutIsTerminal: true);
      expect(resolution, isA<TtsSinkResolved>());
      expect((resolution as TtsSinkResolved).file, isNull);
    });
  });

  group('locateWavDataSizeOffset (§5.4-5 — chunk-walking, never a fixed '
      'offset)', () {
    test('a canonical 16-byte fmt chunk', () {
      final header = _streamingWavHeader(fmtChunkSize: 16);
      // 12 (RIFF/WAVE) + 8 (fmt id+size) + 16 (fmt body) + 4 ('data' id).
      expect(locateWavDataSizeOffset(header), 12 + 8 + 16 + 4);
    });

    test('an extended fmt chunk (extra bytes) still lands on the real '
        '"data" tag, not a fixed 44-byte offset', () {
      final header = _streamingWavHeader(fmtChunkSize: 18);
      expect(locateWavDataSizeOffset(header), 12 + 8 + 18 + 4);
    });

    test('an odd-size chunk is padded to even before the next tag', () {
      final header = _streamingWavHeader(fmtChunkSize: 17);
      expect(locateWavDataSizeOffset(header), 12 + 8 + 17 + 1 + 4);
    });

    test('a truncated/malformed header (no "data" tag found) → null, never '
        'a guess', () {
      final header = dc.ascii.encode('RIFF') + const [0, 0, 0, 0] + dc.ascii.encode('WAVE');
      expect(locateWavDataSizeOffset(header), isNull);
    });
  });

  group('computeWavLengthPatch (§5.4-5 — the two honest lengths)', () {
    test('derives RIFF ChunkSize (total-8) and data size (payload bytes) '
        'from the real file length', () {
      final header = _streamingWavHeader(fmtChunkSize: 16);
      const payloadBytes = 100;
      final totalLength = header.length + payloadBytes;
      final patch = computeWavLengthPatch(header, totalLength);
      expect(patch, isNotNull);
      expect(patch!.riffSizeOffset, 4);
      expect(patch.riffSizeValue, totalLength - 8);
      expect(patch.dataSizeOffset, 12 + 8 + 16 + 4);
      expect(patch.dataSizeValue, payloadBytes);
    });

    test('an unlocatable header → no patch (sentinel stands, honest '
        'abstention)', () {
      final header = dc.ascii.encode('RIFF') + const [0, 0, 0, 0] + dc.ascii.encode('WAVE');
      expect(computeWavLengthPatch(header, 1000), isNull);
    });
  });

  group('patchWavFileLengths (§5.4-5 — end-to-end, a real seekable file)',
      () {
    test('rewrites both sentinel fields to the true lengths, payload bytes '
        'untouched', () async {
      await runInMemoryFs((fs) async {
        final header = _streamingWavHeader(fmtChunkSize: 16);
        final payload = List.generate(37, (i) => i);
        final file = File('out.wav');
        await file.writeAsBytes([...header, ...payload]);

        await patchWavFileLengths(file);

        final bytes = fs.file('out.wav').readAsBytesSync();
        final riffSize =
            bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
        final dataSizeOffset = 12 + 8 + 16 + 4;
        final dataSize = bytes[dataSizeOffset] |
            (bytes[dataSizeOffset + 1] << 8) |
            (bytes[dataSizeOffset + 2] << 16) |
            (bytes[dataSizeOffset + 3] << 24);

        expect(riffSize, bytes.length - 8);
        expect(dataSize, payload.length);
        expect(bytes.sublist(dataSizeOffset + 4), payload);
      });
    });

    test('a non-WAV / unlocatable file is left alone, no crash', () async {
      await runInMemoryFs((fs) async {
        final file = File('not-wav.bin');
        await file.writeAsBytes([1, 2, 3, 4]);
        await patchWavFileLengths(file);
        expect(fs.file('not-wav.bin').readAsBytesSync(), [1, 2, 3, 4]);
      });
    });
  });

  group('tts synthesize honoring the resolved sink (end-to-end)', () {
    test('-o <file> lands the audio bytes in the file', () async {
      await runInMemoryFs((fs) async {
        final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
        final resolution =
            resolveTtsSink('hi.wav', stdoutIsTerminal: false) as TtsSinkResolved;
        final sink = resolution.file!.openWrite();

        await runSynthesize(
          driver,
          textIn: Stream.value(dc.utf8.encode('hello world')),
          out: sink,
        );
        await sink.close();

        final bytes = fs.file('hi.wav').readAsBytesSync();
        expect(dc.ascii.decode(bytes.sublist(0, 4)), 'RIFF');
        expect(bytes.length, greaterThan(44));
      });
    });
  });

  group('ttsFeedbackEnabled (§5.4-6 — the three-way gate)', () {
    test('quiet wins even at a terminal with verbose set', () {
      expect(
        ttsFeedbackEnabled(
            stderrIsTerminal: true, verbose: true, quiet: true),
        isFalse,
      );
    });

    test('terminal, no flags → on', () {
      expect(
        ttsFeedbackEnabled(
            stderrIsTerminal: true, verbose: false, quiet: false),
        isTrue,
      );
    });

    test('pipe, no flags → off', () {
      expect(
        ttsFeedbackEnabled(
            stderrIsTerminal: false, verbose: false, quiet: false),
        isFalse,
      );
    });

    test('pipe + verbose → forced on', () {
      expect(
        ttsFeedbackEnabled(
            stderrIsTerminal: false, verbose: true, quiet: false),
        isTrue,
      );
    });
  });

  group('ttsFormatLabel', () {
    test('no format (class default) → wav', () {
      expect(ttsFormatLabel(null), 'wav');
    });

    test('pcm format → rate label', () {
      final format = PcmOutput(
        PcmTriple(rate: 24000, encoding: PcmEncoding.s16le, channels: 1),
      );
      expect(ttsFormatLabel(format), 'pcm 24000Hz');
    });
  });

  group('the three beats — pure line formatters', () {
    test('intent: target · format, voice omitted when unset', () {
      expect(
        ttsIntentLine(target: 'hi.wav', format: 'wav'),
        'tts: text → hi.wav · wav',
      );
    });

    test('intent: voice appended when requested', () {
      expect(
        ttsIntentLine(target: 'stdout', format: 'wav', voice: 'alloy'),
        'tts: text → stdout · wav · voice alloy',
      );
    });

    test('resolved: model · format, voice appended when requested', () {
      expect(
        ttsResolvedLine(model: 'tts-1', format: 'wav', voice: 'alloy'),
        'tts: tts-1 · wav · alloy',
      );
    });

    test('resolved: no voice → model · format only', () {
      expect(
        ttsResolvedLine(model: 'tts-1', format: 'wav'),
        'tts: tts-1 · wav',
      );
    });

    test('completion: bytes · wall-clock', () {
      expect(
        ttsCompletionLine(bytes: 128, elapsed: const Duration(milliseconds: 42)),
        'tts: 128 bytes · 42ms',
      );
    });
  });

  group('tts synthesize feedback channel (end-to-end)', () {
    test('feedbackEnabled: false → err sink stays empty', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final err = _CaptureSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hello world')),
        out: _CaptureSink(),
        err: err,
      );

      expect(err.text, isEmpty);
    });

    test('feedbackEnabled: true → resolved + completion beats land on err, '
        'never on out', () async {
      final driver = openaiTtsDriver(model: 'tts-1', apiKey: 'fake');
      final err = _CaptureSink();
      final out = _CaptureSink();

      await runSynthesize(
        driver,
        textIn: Stream.value(dc.utf8.encode('hello world')),
        out: out,
        err: err,
        feedbackEnabled: true,
      );

      expect(err.text, contains('fake-tts-1'));
      expect(err.text, contains('bytes'));
      // out is binary audio, not necessarily valid UTF-8 — compare raw bytes.
      expect(
        dc.ascii
            .decode(out.bytes, allowInvalid: true)
            .contains('fake-tts-1'),
        isFalse,
      );
    });
  });
}

// Captures bytes/text written to an injected IOSink — the same minimal shape
// as stt's face_test.dart `BytesIOSink`.
class _CaptureSink implements IOSink {
  final _bytes = BytesBuilder();
  List<int> get bytes => _bytes.toBytes();
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
