/// D3 tests — function call widget + Block (non-streaming) dispatch.
library;

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:bentos_userland/chat_render.dart';
import 'package:term_glyph/term_glyph.dart' as tg;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  callTests();
  blockTests();
}

// ---------------------------------------------------------------------------
// Helpers (same pattern as chat_render_test.dart)
// ---------------------------------------------------------------------------

Future<String> render(
  List<String> lines, {
  bool ansi = false,
  bool unicode = false,
  bool thinking = true,
  bool calls = true,
  bool compact = false,
  bool boundary = false,
  int width = 0,
}) async {
  tg.ascii = !unicode;
  ansiColorDisabled = !ansi;
  final backend = ansi ? const AnsiBackend() : const PlainBackend();
  final out = StringBuffer();
  final options = RenderOptions(
    thinking: thinking,
    calls: calls,
    ansi: ansi,
    unicode: unicode,
    compact: compact,
    boundary: boundary,
    width: width,
    backend: backend,
    out: stdout,
  );
  await ChatRenderer(options, out: out, lines: Stream.fromIterable(lines))
      .run();
  return out.toString();
}

List<String> fixture(String name) =>
    File('test/chat-render/fixtures/$name.jsonl').readAsLinesSync();

// ---------------------------------------------------------------------------
// Function call — streaming triads
// ---------------------------------------------------------------------------

void callTests() {
  group('function call', () {
    test('function-call-single: committed line plain snapshot', () async {
      final out = await render(fixture('function-call-single'));
      // off-TTY / no-ansi → no forming, just committed line
      expect(out, '> get_weather {"city":"São Paulo","unit":"celsius"}\n');
    });

    test('function-call-single: Unicode arrow', () async {
      final out =
          await render(fixture('function-call-single'), unicode: true);
      expect(out, startsWith('→ get_weather '));
      expect(out, contains('"city":"São Paulo"'));
    });

    test('function-call-single: ANSI — args dimmed', () async {
      final out = await render(
        fixture('function-call-single'),
        ansi: true,
        unicode: true,
      );
      // Forming is on when ansi=true; output starts with forming (no NL) then
      // \r\x1B[K + committed line. Check committed content is present.
      expect(out, contains('→ get_weather'));
      expect(out, contains('\x1B[2m')); // dim on args
      expect(out, contains('"city":"São Paulo"'));
    });

    test('function-call-multi: two calls, same index — no state leak', () async {
      final out = await render(fixture('function-call-multi'));
      final lines = out.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(2));
      expect(lines[0], '> get_weather {"city":"Tokyo"}');
      expect(lines[1], '> get_time {"tz":"Asia/Tokyo"}');
    });

    test('function-call-multi: second call does not inherit first args', () async {
      final out = await render(fixture('function-call-multi'));
      // First call args must not bleed into second call line
      expect(out, isNot(contains('Tokyo"}{"tz"')));
      // Each call has its own exact args
      expect(out, contains('{"city":"Tokyo"}'));
      expect(out, contains('{"tz":"Asia/Tokyo"}'));
    });

    test('--no-calls suppresses call lines entirely', () async {
      final out = await render(fixture('function-call-single'), calls: false);
      expect(out, isEmpty);
    });

    test('--no-calls on multi: both calls suppressed', () async {
      final out = await render(fixture('function-call-multi'), calls: false);
      expect(out, isEmpty);
    });

    test('multi-block-text-and-fn: speech then call', () async {
      final out = await render(fixture('multi-block-text-and-fn'));
      expect(out, startsWith('I will check that.'));
      expect(out, contains('> search {"q":"bentos OS"}'));
    });
  });
}

// ---------------------------------------------------------------------------
// Block (non-streaming)
// ---------------------------------------------------------------------------

void blockTests() {
  group('Block (non-streaming)', () {
    test('non-streaming-text: plain snapshot', () async {
      final out = await render(fixture('non-streaming-text'));
      expect(out, 'The quick brown fox jumps over the lazy dog.');
    });

    test('non-streaming-text: same output as streaming text-simple', () async {
      final streaming = await render(fixture('text-simple'));
      final block = await render(fixture('non-streaming-text'));
      expect(block, streaming);
    });

    test('non-streaming-fn: committed line, no forming phase', () async {
      final out = await render(fixture('non-streaming-fn'));
      expect(out, '> get_weather {"city":"London"}\n');
    });

    test('non-streaming-fn: Unicode arrow', () async {
      final out = await render(fixture('non-streaming-fn'), unicode: true);
      expect(out, '→ get_weather {"city":"London"}\n');
    });

    test('non-streaming-fn: --no-calls suppresses', () async {
      final out = await render(fixture('non-streaming-fn'), calls: false);
      expect(out, isEmpty);
    });

    test('non-streaming-fn: ANSI — args dimmed', () async {
      final out = await render(
        fixture('non-streaming-fn'),
        ansi: true,
        unicode: true,
      );
      expect(out, contains('→ get_weather'));
      expect(out, contains('\x1B[2m')); // dim on args
    });
  });
}
