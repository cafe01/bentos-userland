/// Resolved runtime options for chat-render.
///
/// All auto-detects are resolved at construction time; the renderer and widgets
/// see only concrete booleans.
library;

import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:term_glyph/term_glyph.dart' as tg;

import 'backend/ansi_backend.dart';
import 'backend/plain_backend.dart';
import 'backend/render_backend.dart';

class RenderOptions {
  RenderOptions({
    required this.thinking,
    required this.calls,
    required this.ansi,
    required this.unicode,
    required this.compact,
    required this.boundary,
    required this.width,
    required this.backend,
    IOSink? out,
  }) : out = out ?? stdout;

  final bool thinking;
  final bool calls;
  final bool ansi;
  final bool unicode;
  final bool compact;
  final bool boundary;

  /// Column budget for fixed chrome (call-cards). 0 = no limit.
  final int width;

  final RenderBackend backend;

  /// Output sink — stdout by default, injectable for tests.
  final IOSink out;

  /// Build [RenderOptions] from parsed arg values and the current environment.
  factory RenderOptions.fromArgs({
    required bool thinking,
    required bool calls,
    required bool? ansiOverride,
    required bool? unicodeOverride,
    required bool compact,
    required bool? boundaryOverride,
    required int? widthOverride,
    IOSink? out,
  }) {
    final isTty = stdout.hasTerminal;

    final ansi = ansiOverride ?? isTty;
    final unicode = unicodeOverride ?? _localeIsUtf8();
    final boundary = boundaryOverride ?? isTty;
    final width = widthOverride ?? (isTty ? stdout.terminalColumns : 0);

    // Wire the two global flags before constructing the backends.
    tg.ascii = !unicode;
    ansiColorDisabled = !ansi; // keep ansicolor in sync with our resolved flag

    final backend = ansi ? const AnsiBackend() : const PlainBackend();

    return RenderOptions(
      thinking: thinking,
      calls: calls,
      ansi: ansi,
      unicode: unicode,
      compact: compact,
      boundary: boundary,
      width: width,
      backend: backend,
      out: out,
    );
  }
}

/// Returns true when the process locale signals UTF-8 support.
bool _localeIsUtf8() {
  for (final key in ['LC_ALL', 'LC_CTYPE', 'LANG']) {
    final val = Platform.environment[key];
    if (val != null) {
      final upper = val.toUpperCase();
      if (upper.contains('UTF-8') || upper.contains('UTF8')) return true;
    }
  }
  return false;
}
