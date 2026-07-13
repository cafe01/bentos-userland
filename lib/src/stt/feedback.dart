/// The `stt` stderr feedback channel (§1.1/§5.4-6 — the human channel).
///
/// Pure decisions and pure line formatters, no stream touched directly: the
/// TTY sense is injected (same discipline as [resolveSttInput]) so the gate
/// and the three beats are testable without a pty. Never a byte of this
/// reaches stdout — the mirror of `tts`'s feedback channel.
library;

/// Whether the channel is on — identical law to `tts`'s gate (`--quiet`
/// always wins; a terminal or `--verbose` turns it on otherwise).
bool sttFeedbackEnabled({
  required bool stderrIsTerminal,
  required bool verbose,
  required bool quiet,
}) {
  if (quiet) return false;
  return stderrIsTerminal || verbose;
}

/// Beat 1 — before the device opens: what was requested. [source] names the
/// audio's nature (`audio`, `live audio`); [format] carries verb-specific
/// context beyond language (`live`'s requested rate).
String sttIntentLine({
  required String source,
  String? language,
  String? format,
}) {
  final line = StringBuffer('stt: $source → stdout');
  if (format != null) line.write(' · $format');
  if (language != null) line.write(' · language $language');
  return line.toString();
}

/// Beat 2 — after the device opens: what it settled on, [model] read from
/// `STT_GET_INFO` (§5.3 — no new device surface). [language] echoes the
/// requested hint, never a detected result (unknown until `complete`).
String sttResolvedLine({
  required String model,
  String? language,
  String? format,
}) {
  final line = StringBuffer('stt: $model');
  if (format != null) line.write(' · $format');
  if (language != null) line.write(' · $language');
  return line.toString();
}

/// Beat 3 — the completion summary: the face's own measure.
String sttCompletionLine({required int words, required Duration elapsed}) =>
    'stt: $words words · ${elapsed.inMilliseconds}ms';
