/// Tests for chat-render — deterministic rendering against fixtures.
///
/// All tests run with --no-ansi --no-unicode (plain text + ASCII glyphs) for
/// full string determinism. ANSI groups validate SGR codes.
library;

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:chat_inference/chat_inference.dart';
import 'package:chat_render/chat_render.dart';
import 'package:term_glyph/term_glyph.dart' as tg;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  speechTests();
  thinkingTests();
  signatureTests();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Render a list of JSONL event lines and return the output string.
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
    out: stdout, // unused — renderer uses the injected StringSink
  );
  await ChatRenderer(options, out: out, lines: Stream.fromIterable(lines))
      .run();
  return out.toString();
}

/// Read a fixture file's lines.
List<String> fixture(String name) =>
    File('fixtures/$name.jsonl').readAsLinesSync();

// ---------------------------------------------------------------------------
// Speech — text-simple
// ---------------------------------------------------------------------------

void speechTests() {
  group('speech', () {
    test('deltas concatenated, no prefix, no wrapping', () async {
      final out = await render(fixture('text-simple'));
      expect(out, 'The quick brown fox jumps over the lazy dog.');
    });

    test('ANSI form is identical — speech carries no styling', () async {
      final out =
          await render(fixture('text-simple'), ansi: true, unicode: true);
      expect(out, 'The quick brown fox jumps over the lazy dog.');
    });

    test('empty stdin → empty output', () async {
      expect(await render([]), isEmpty);
    });

    test('blank lines in stream are skipped', () async {
      final lines = [
        encodeEventJson(const TextStart(0)),
        '',
        encodeEventJson(const TextDelta(index: 0, text: 'hello')),
        encodeEventJson(const TextStop(0)),
      ];
      expect(await render(lines), 'hello');
    });

    test('malformed line returns exit 1', () async {
      tg.ascii = true;
      final out = StringBuffer();
      final options = RenderOptions(
        thinking: true,
        calls: true,
        ansi: false,
        unicode: false,
        compact: false,
        boundary: false,
        width: 0,
        backend: const PlainBackend(),
        out: stdout,
      );
      final code = await ChatRenderer(
        options,
        out: out,
        lines: Stream.fromIterable([
          encodeEventJson(const TextStart(0)),
          'not-json{',
        ]),
      ).run();
      expect(code, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// Thinking — thinking-and-text, thinking-with-signature
// ---------------------------------------------------------------------------

void thinkingTests() {
  group('thinking', () {
    test('thinking-and-text: full plain snapshot (ASCII glyphs)', () async {
      final out = await render(fixture('thinking-and-text'));
      expect(
        out,
        ', thinking\n'
        '  Let me reason about this step by step.'
        ' First, I consider the constraints.\n'
        "'\n"
        'The answer is 42.',
      );
    });

    test('thinking-and-text: Unicode glyphs', () async {
      final out =
          await render(fixture('thinking-and-text'), unicode: true);
      expect(out, startsWith('┌ thinking\n'));
      expect(out, contains('  Let me reason about this step by step.'));
      expect(out, contains('└\n'));
      expect(out, endsWith('The answer is 42.'));
    });

    test('ANSI: markers dim (SGR 2), body dim+italic (SGR 2;3)', () async {
      final out = await render(
        fixture('thinking-and-text'),
        ansi: true,
        unicode: true,
      );
      expect(out, contains('\x1B[2m')); // dim on markers
      expect(out, contains('\x1B[2;3m')); // dim+italic on body
      expect(out, contains('┌ thinking'));
      expect(out, contains('└'));
      expect(out, contains('The answer is 42.')); // speech unaffected
    });

    test('--no-thinking suppresses block; speech still renders', () async {
      final out =
          await render(fixture('thinking-and-text'), thinking: false);
      expect(out, isNot(contains('thinking')));
      expect(out, 'The answer is 42.');
    });

    test('--compact: inline lead, no close frame', () async {
      final out =
          await render(fixture('thinking-and-text'), compact: true);
      // ASCII compact glyph = | (verticalLineTripleDash ASCII fallback)
      expect(out, startsWith('| thinking: '));
      // Body on same line
      expect(out, contains('Let me reason about this step by step.'));
      // No closing frame (no ' on its own line)
      expect(out, isNot(matches(RegExp(r"^'$", multiLine: true))));
      // Speech follows
      expect(out, endsWith('The answer is 42.'));
    });

    test('thinking-with-signature: SignatureDelta silently dropped', () async {
      final out = await render(fixture('thinking-with-signature'));
      expect(out, isNot(contains('EqoB'))); // no signature bytes in output
      expect(out, contains(', thinking\n'));
      expect(out, contains('  I need to think carefully here.'));
      expect(out, contains("'\n"));
      expect(out, endsWith('Here is my response.'));
    });

    test('thinking-with-signature: plain snapshot', () async {
      final out = await render(fixture('thinking-with-signature'));
      expect(
        out,
        ', thinking\n'
        '  I need to think carefully here.\n'
        "'\n"
        'Here is my response.',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// SignatureDelta — isolated drop guarantee
// ---------------------------------------------------------------------------

void signatureTests() {
  group('signature', () {
    test('standalone SignatureDelta → empty output', () async {
      final lines = [
        encodeEventJson(
          const SignatureDelta(index: 0, signature: 'abc123'),
        ),
      ];
      expect(await render(lines), isEmpty);
    });

    test('SignatureDelta mid-thinking block does not break the block', () async {
      final lines = [
        encodeEventJson(const ThinkingStart(0)),
        encodeEventJson(const ThinkingDelta(index: 0, text: 'before')),
        encodeEventJson(
            const SignatureDelta(index: 0, signature: 'opaque')),
        encodeEventJson(const ThinkingDelta(index: 0, text: ' after')),
        encodeEventJson(const ThinkingStop(0)),
      ];
      final out = await render(lines);
      expect(out, contains('  before after'));
      expect(out, isNot(contains('opaque')));
    });
  });
}
