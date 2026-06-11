/// The backend interface for chat-render widgets.
///
/// Widgets route through this interface — never calling ansicolor or term_glyph
/// inline. A Flutter backend can implement the same interface to render the
/// same widget ontology to GUI.
library;

/// Semantic styling roles. Each role maps to a visual treatment in the
/// concrete backend; the widget itself never names a color or SGR code.
enum StyleRole {
  /// Assistant speech — the primary content. Unmarked baseline.
  speech,

  /// Reasoning trace — dim + italic (ANSI) or plain (--no-ansi).
  thinking,

  /// Tool/function call — accent hue for name, dim for args.
  call,

  /// Turn-end marker for quiet stop reasons (dim).
  boundary,

  /// Turn-end marker for stop reasons that demand attention (warning hue).
  notice,
}

/// Named glyphs used by the widget catalog. The backend resolves each name to
/// either a Unicode character (default) or its same-width ASCII fallback
/// (--no-unicode / --ascii).
enum GlyphName {
  /// `┌` / `,`  — thinking block open.
  thinkingOpen,

  /// `└` / `'`  — thinking block close.
  thinkingClose,

  /// `┊` / `|`  — thinking compact inline lead.
  thinkingCompact,

  /// `→` / `>`  — function-call arrow and function_call boundary.
  callArrow,

  /// `─` / `-`  — stop_sequence boundary line.
  boundaryLine,

  /// `⚠` / `!`  — max_tokens / content_filter warning.
  boundaryWarning,
}

/// Thin backend interface. Two implementations ship: [AnsiBackend] (ansicolor
/// + term_glyph unicode) and [PlainBackend] (no styling + term_glyph ASCII).
abstract interface class RenderBackend {
  /// Wrap [text] with the visual treatment for [role]. Returns [text] unchanged
  /// when styling is disabled (plain backend or --no-ansi).
  String style(String text, StyleRole role);

  /// Resolve [name] to the terminal-appropriate glyph string.
  String glyph(GlyphName name);
}
