/// ChatRenderer — dispatches ChatEvent JSONL from stdin to the widget catalog.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chat_inference/chat_inference.dart';

import 'backend/render_backend.dart';
import 'render_options.dart';

class ChatRenderer {
  ChatRenderer(
    this.options, {
    StringSink? out,
    Stream<String>? lines,
  })  : _out = out ?? options.out,
        _lines = lines ??
            stdin
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
        _callArgs = StringBuffer();

  final RenderOptions options;
  final StringSink _out;
  final Stream<String> _lines;

  // ---------------------------------------------------------------------------
  // Call widget state — reset at every FunctionCallStop.
  // index is NOT the key; we track "currently open call" as a slot.
  // ---------------------------------------------------------------------------
  String? _callName; // non-null while a call block is open
  final StringBuffer _callArgs;

  // Track whether the last character written was a newline so boundary markers
  // always start on a fresh line.
  bool _atLineStart = true;

  // ---------------------------------------------------------------------------
  // Output helpers — maintain _atLineStart for boundary newline guards.
  // ---------------------------------------------------------------------------

  void _write(String s) {
    if (s.isEmpty) return;
    _out.write(s);
    _atLineStart = s.endsWith('\n');
  }

  void _writeln([String s = '']) {
    _out.writeln(s);
    _atLineStart = true;
  }

  void _ensureNewline() {
    if (!_atLineStart) _writeln();
  }

  // ---------------------------------------------------------------------------

  Future<int> run() async {
    var lineNum = 0;
    await for (final line in _lines) {
      lineNum++;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      ChatEvent event;
      try {
        event = decodeEventJson(trimmed);
      } catch (e) {
        stderr.writeln('chat-render: line $lineNum: $e');
        return 1;
      }

      _dispatch(event);
    }

    if (_out case final IOSink sink) await sink.flush();
    return 0;
  }

  void _dispatch(ChatEvent event) {
    switch (event) {
      // --- Speech ---
      case TextStart():
        break;
      case TextDelta(:final text):
        _write(text);
      case TextStop():
        break;

      // --- Thinking ---
      case ThinkingStart():
        if (options.thinking) _thinkingOpen();
      case ThinkingDelta(:final text):
        if (options.thinking) _thinkingBody(text);
      case ThinkingStop():
        if (options.thinking) _thinkingClose();

      // --- Signature — silently dropped; opaque round-trip data ---
      case SignatureDelta():
        break;

      // --- Function calls ---
      case FunctionCallStart(:final name):
        if (options.calls) _callOpen(name);
      case FunctionArgsDelta(:final partialJson):
        if (options.calls) _callArgs.write(partialJson);
      case FunctionCallStop():
        if (options.calls) _callCommit();

      // --- Non-streaming whole block ---
      case Block(:final content):
        _dispatchBlock(content);

      // --- Turn boundary ---
      case Complete(:final metadata):
        _boundary(metadata);
    }
  }

  // ---------------------------------------------------------------------------
  // Thinking widget
  // ---------------------------------------------------------------------------

  void _thinkingOpen() {
    final b = options.backend;
    if (options.compact) {
      _write(
        '${b.style(b.glyph(GlyphName.thinkingCompact), StyleRole.boundary)} thinking: ',
      );
    } else {
      _writeln(
        b.style(
          '${b.glyph(GlyphName.thinkingOpen)} thinking',
          StyleRole.boundary,
        ),
      );
      _write('  '); // initial 2-col indent for the body
    }
  }

  void _thinkingBody(String text) {
    final b = options.backend;
    if (options.compact) {
      _write(b.style(text, StyleRole.thinking));
    } else {
      // Replace model-emitted \n with \n + indent. Never inject \n ourselves.
      _write(b.style(text.replaceAll('\n', '\n  '), StyleRole.thinking));
    }
  }

  void _thinkingClose() {
    final b = options.backend;
    if (options.compact) {
      _writeln();
    } else {
      _writeln();
      _writeln(
          b.style(b.glyph(GlyphName.thinkingClose), StyleRole.boundary));
    }
  }

  // ---------------------------------------------------------------------------
  // Call widget
  //
  // Forming (TTY / ansi=true): emits `→ name …` at Start, then rewrites the
  // line at Stop with \r + erase + committed form.
  // Off-TTY / --no-ansi: nothing at Start; committed line only at Stop.
  //
  // State reset at every Stop — index is not the key across a turn.
  // ---------------------------------------------------------------------------

  bool get _forming => options.ansi;

  void _callOpen(String name) {
    _callName = name;
    _callArgs.clear();
    if (_forming) {
      final b = options.backend;
      _write('${b.glyph(GlyphName.callArrow)} $name …');
    }
  }

  void _callCommit() {
    final b = options.backend;
    final name = _callName ?? '';
    final args = b.style(_callArgs.toString(), StyleRole.boundary);
    final committed = '${b.glyph(GlyphName.callArrow)} $name $args';

    if (_forming) {
      // \r moves to line start; \x1B[K erases to end of line.
      _write('\r\x1B[K$committed\n');
    } else {
      _writeln(committed);
    }

    // Reset — next call (even same index) starts fresh.
    _callName = null;
    _callArgs.clear();
  }

  // ---------------------------------------------------------------------------
  // Turn boundary widget — Complete event.
  //
  // Governed by --[no-]boundary (off by default in pipes).
  // --compact suppresses end_turn and stop_sequence; never suppresses notices.
  // ---------------------------------------------------------------------------

  void _boundary(ChatMetadata metadata) {
    if (!options.boundary) return;
    // end_turn + compact emits nothing — skip the newline guard too.
    if (metadata.stopReason is EndTurn && options.compact) return;
    // stop_sequence + compact emits nothing.
    if (metadata.stopReason is StopSequence && options.compact) return;
    _ensureNewline();
    final b = options.backend;

    switch (metadata.stopReason) {
      case EndTurn():
        _writeln(); // compact case already returned above

      case FunctionCall():
        // Always shown — the loop continues; this is a signal, not chrome.
        _writeln(
          b.style(
            '${b.glyph(GlyphName.callArrow)} (awaiting tool result)',
            StyleRole.boundary,
          ),
        );

      case MaxTokens():
        // Notice — never compacted away.
        _writeln(
          b.style(
            '${b.glyph(GlyphName.boundaryWarning)} truncated — max_tokens',
            StyleRole.notice,
          ),
        );

      case StopSequence():
        // compact case already returned above
        _writeln(
          b.style(
            '${b.glyph(GlyphName.boundaryLine)} (stop sequence)',
            StyleRole.boundary,
          ),
        );

      case ContentFilter():
        // Notice — never compacted away.
        _writeln(
          b.style(
            '${b.glyph(GlyphName.boundaryWarning)} stopped — content_filter',
            StyleRole.notice,
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Block dispatch — whole block, no forming phase for calls.
  // ---------------------------------------------------------------------------

  void _dispatchBlock(ChatContent content) {
    final b = options.backend;
    switch (content) {
      case TextContent(:final text):
        _write(text);

      case ThinkingContent(:final text):
        if (!options.thinking) return;
        _thinkingOpen();
        _thinkingBody(text);
        _thinkingClose();

      case FunctionCallContent(:final name, :final arguments):
        if (!options.calls) return;
        // No forming phase — the block arrived whole.
        final args = b.style(jsonEncode(arguments), StyleRole.boundary);
        _writeln('${b.glyph(GlyphName.callArrow)} $name $args');

      // Opaque / unrenderable content kinds — silently skip.
      case BinaryContent():
      case RedactedThinkingContent():
      case FunctionResultContent():
      case CachePointContent():
        break;
    }
  }
}
