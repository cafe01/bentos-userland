/// ANSI backend — ansicolor for color, a tiny SGR helper for dim + italic
/// (ansicolor 2.x covers 256-color but not SGR 2/3), and term_glyph Unicode.
library;

import 'package:ansicolor/ansicolor.dart';
import 'package:term_glyph/term_glyph.dart' as tg;

import 'render_backend.dart';

// ---------------------------------------------------------------------------
// Mini SGR helper — supplements ansicolor for dim (SGR 2) + italic (SGR 3).
// Respects [ansiColorDisabled] so --no-ansi turns these off consistently.
// ---------------------------------------------------------------------------

const _esc = '\x1B[';
const _reset = '${_esc}0m';

String _sgr(String text, List<int> codes) {
  if (ansiColorDisabled) return text;
  return '$_esc${codes.join(';')}m$text$_reset';
}

String _dim(String text) => _sgr(text, [2]);
String _italic(String text) => _sgr(text, [3]);
String _dimItalic(String text) => _sgr(text, [2, 3]);

// ---------------------------------------------------------------------------
// AnsiPen instances for color roles.
// ---------------------------------------------------------------------------

final _yellowPen = AnsiPen()..yellow();

// ---------------------------------------------------------------------------
// AnsiBackend
// ---------------------------------------------------------------------------

class AnsiBackend implements RenderBackend {
  const AnsiBackend();

  @override
  String style(String text, StyleRole role) => switch (role) {
        StyleRole.speech => text,
        StyleRole.thinking => _dimItalic(text),
        StyleRole.call => text, // name/args styled separately in the widget
        StyleRole.boundary => _dim(text),
        StyleRole.notice => _yellowPen.write(text),
      };

  /// Style helpers exposed for widget-level granularity (e.g. dim frame,
  /// italic body) without a second [StyleRole] per sub-element.
  String dim(String text) => _dim(text);
  String italic(String text) => _italic(text);
  String dimItalic(String text) => _dimItalic(text);

  @override
  String glyph(GlyphName name) => switch (name) {
        GlyphName.thinkingOpen => tg.topLeftCorner,
        GlyphName.thinkingClose => tg.bottomLeftCorner,
        GlyphName.thinkingCompact => tg.verticalLineTripleDash,
        GlyphName.callArrow => tg.rightArrow,
        GlyphName.boundaryLine => tg.horizontalLine,
        GlyphName.boundaryWarning => '⚠',
      };
}
