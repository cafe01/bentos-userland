/// D4 tests — turn boundary widget + full 12-fixture sweep.
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
  boundaryTests();
  sweepTests();
}

// ---------------------------------------------------------------------------
// Helpers
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
// Boundary widget — all 5 stop_reason cases
// ---------------------------------------------------------------------------

void boundaryTests() {
  group('boundary', () {
    // --- end_turn ---

    test('end_turn: blank line when boundary=true', () async {
      final out = await render(fixture('text-simple'), boundary: true);
      expect(out, endsWith('\n\n')); // content line + blank line
    });

    test('end_turn: no boundary marker when boundary=false (default)', () async {
      final out = await render(fixture('text-simple'));
      expect(out, 'The quick brown fox jumps over the lazy dog.');
      expect(out, isNot(endsWith('\n\n')));
    });

    test('end_turn + compact: blank line suppressed', () async {
      final out =
          await render(fixture('text-simple'), boundary: true, compact: true);
      // compact suppresses end_turn — no trailing blank line
      expect(out, 'The quick brown fox jumps over the lazy dog.');
    });

    // --- function_call ---

    test('function_call: → (awaiting tool result) dim', () async {
      final out =
          await render(fixture('function-call-single'), boundary: true);
      expect(out, contains('> (awaiting tool result)\n'));
    });

    test('function_call + compact: awaiting line still shown', () async {
      final out = await render(
        fixture('function-call-single'),
        boundary: true,
        compact: true,
      );
      expect(out, contains('> (awaiting tool result)\n'));
    });

    test('function_call: Unicode glyph', () async {
      final out = await render(
        fixture('function-call-single'),
        boundary: true,
        unicode: true,
      );
      expect(out, contains('→ (awaiting tool result)\n'));
    });

    // --- max_tokens ---

    test('max_tokens: warning on its own line', () async {
      final out =
          await render(fixture('complete-max-tokens'), boundary: true);
      expect(out, contains('\n! truncated — max_tokens\n'));
    });

    test('max_tokens + compact: warning still shown (never compacted)', () async {
      final out = await render(
        fixture('complete-max-tokens'),
        boundary: true,
        compact: true,
      );
      expect(out, contains('! truncated — max_tokens\n'));
    });

    test('max_tokens: ANSI notice = yellow SGR', () async {
      final out = await render(
        fixture('complete-max-tokens'),
        boundary: true,
        ansi: true,
        unicode: true,
      );
      expect(out, contains('\x1B[38;5;3m')); // yellow
      expect(out, contains('⚠ truncated — max_tokens'));
    });

    test('max_tokens: no boundary when boundary=false', () async {
      final out = await render(fixture('complete-max-tokens'));
      expect(out, isNot(contains('truncated')));
    });

    // --- stop_sequence ---

    test('stop_sequence: dim marker on its own line', () async {
      final out =
          await render(fixture('complete-stop-sequence'), boundary: true);
      expect(out, contains('\n- (stop sequence)\n'));
    });

    test('stop_sequence + compact: marker suppressed', () async {
      final out = await render(
        fixture('complete-stop-sequence'),
        boundary: true,
        compact: true,
      );
      expect(out, isNot(contains('stop sequence')));
    });

    test('stop_sequence: Unicode glyph', () async {
      final out = await render(
        fixture('complete-stop-sequence'),
        boundary: true,
        unicode: true,
      );
      expect(out, contains('─ (stop sequence)\n'));
    });

    // --- content_filter ---

    test('content_filter: warning (no prior speech)', () async {
      final out =
          await render(fixture('complete-content-filter'), boundary: true);
      expect(out, '! stopped — content_filter\n');
    });

    test('content_filter + compact: warning still shown', () async {
      final out = await render(
        fixture('complete-content-filter'),
        boundary: true,
        compact: true,
      );
      expect(out, contains('! stopped — content_filter\n'));
    });

    test('content_filter: ANSI notice = yellow SGR', () async {
      final out = await render(
        fixture('complete-content-filter'),
        boundary: true,
        ansi: true,
        unicode: true,
      );
      expect(out, contains('\x1B[38;5;3m'));
      expect(out, contains('⚠ stopped — content_filter'));
    });

    // --- boundary placement ---

    test('max_tokens: marker on its own line even when content has no trailing newline', () async {
      // complete-max-tokens has speech with no trailing \n before Complete
      final out =
          await render(fixture('complete-max-tokens'), boundary: true);
      final lines = out.split('\n');
      // Last non-empty line is the warning
      final nonEmpty = lines.where((l) => l.isNotEmpty).toList();
      expect(nonEmpty.last, '! truncated — max_tokens');
    });
  });
}

// ---------------------------------------------------------------------------
// Full 12-fixture sweep — no-ansi no-unicode, boundary=false (default pipe)
// ---------------------------------------------------------------------------

void sweepTests() {
  group('sweep (--no-ansi --no-unicode, boundary off)', () {
    test('text-simple', () async {
      expect(
        await render(fixture('text-simple')),
        'The quick brown fox jumps over the lazy dog.',
      );
    });

    test('thinking-and-text', () async {
      expect(
        await render(fixture('thinking-and-text')),
        ', thinking\n'
        '  Let me reason about this step by step.'
        ' First, I consider the constraints.\n'
        "'\n"
        'The answer is 42.',
      );
    });

    test('thinking-with-signature', () async {
      expect(
        await render(fixture('thinking-with-signature')),
        ', thinking\n'
        '  I need to think carefully here.\n'
        "'\n"
        'Here is my response.',
      );
    });

    test('function-call-single', () async {
      expect(
        await render(fixture('function-call-single')),
        '> get_weather {"city":"São Paulo","unit":"celsius"}\n',
      );
    });

    test('function-call-multi: two lines, no state leak', () async {
      final out = await render(fixture('function-call-multi'));
      expect(out, '> get_weather {"city":"Tokyo"}\n> get_time {"tz":"Asia/Tokyo"}\n');
    });

    test('multi-block-text-and-fn', () async {
      final out = await render(fixture('multi-block-text-and-fn'));
      expect(out, 'I will check that.> search {"q":"bentos OS"}\n');
    });

    test('non-streaming-text: identical to text-simple', () async {
      final streaming = await render(fixture('text-simple'));
      final block = await render(fixture('non-streaming-text'));
      expect(block, streaming);
    });

    test('non-streaming-fn', () async {
      expect(
        await render(fixture('non-streaming-fn')),
        '> get_weather {"city":"London"}\n',
      );
    });

    test('complete-max-tokens: content only (no boundary)', () async {
      expect(
        await render(fixture('complete-max-tokens')),
        'This is a very long response that gets cut',
      );
    });

    test('complete-stop-sequence: content only (no boundary)', () async {
      expect(
        await render(fixture('complete-stop-sequence')),
        'Here is the output:',
      );
    });

    test('complete-with-reasoning-tokens: thinking + speech', () async {
      expect(
        await render(fixture('complete-with-reasoning-tokens')),
        ', thinking\n'
        '  Extended thinking engaged.\n'
        "'\n"
        'After careful consideration: 42.',
      );
    });

    test('complete-content-filter: empty output (no speech, no boundary)', () async {
      expect(await render(fixture('complete-content-filter')), isEmpty);
    });
  });
}
