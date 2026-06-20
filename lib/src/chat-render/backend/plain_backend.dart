/// Plain backend — no ANSI styling, term_glyph ASCII glyphs.
/// The legibility floor: `--no-ansi --no-unicode`.
library;

import 'package:term_glyph/term_glyph.dart' as tg;

import 'render_backend.dart';

class PlainBackend implements RenderBackend {
  const PlainBackend();

  @override
  String style(String text, StyleRole role) => text;

  @override
  String glyph(GlyphName name) {
    // ASCII mode must be set before first access; the caller sets glyph.ascii
    // based on --[no-]unicode. Re-reading here means the glyph set is already
    // in ASCII mode when PlainBackend is constructed.
    return switch (name) {
      GlyphName.thinkingOpen => tg.topLeftCorner,
      GlyphName.thinkingClose => tg.bottomLeftCorner,
      GlyphName.thinkingCompact => tg.verticalLineTripleDash,
      GlyphName.callArrow => tg.rightArrow,
      GlyphName.boundaryLine => tg.horizontalLine,
      GlyphName.boundaryWarning => '!',
    };
  }
}
