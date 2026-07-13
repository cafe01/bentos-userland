/// The `tts` stderr feedback channel (§1.1/§5.4-6 — the human channel).
///
/// Pure decisions and pure line formatters, no stream touched directly: the
/// TTY sense is injected (same discipline as [resolveTtsSink]/
/// [resolveTtsTextSource]) so the gate and the three beats are testable
/// without a pty. Never a byte of this reaches stdout.
library;

import 'package:tts_inference/tts_inference.dart';

/// Whether the channel is on: `--quiet` always wins (even at a terminal);
/// otherwise a terminal or `--verbose` turns it on (verbose forces it under
/// a pipe too — `-v` no longer gates extra content, only visibility, since
/// the three beats already carry the full run metadata, tech-spec §5.4-6).
bool ttsFeedbackEnabled({
  required bool stderrIsTerminal,
  required bool verbose,
  required bool quiet,
}) {
  if (quiet) return false;
  return stderrIsTerminal || verbose;
}

/// The output-format label shared by the intent and resolved beats — the
/// same switch [SynthesizeCommand] already used inline for its old `-v`
/// bracket, now the one place it lives.
String ttsFormatLabel(TtsOutputFormat? format) => switch (format) {
      PcmOutput(:final triple) => 'pcm ${triple.rate}Hz',
      _ => 'wav',
    };

/// Beat 1 — before the device opens: what was requested.
String ttsIntentLine({
  required String target,
  required String format,
  String? voice,
}) {
  final line = StringBuffer('tts: text → $target · $format');
  if (voice != null) line.write(' · voice $voice');
  return line.toString();
}

/// Beat 2 — after the device opens: what it settled on, [model] read from
/// `TTS_GET_INFO` (§5.3 — no new device surface).
String ttsResolvedLine({
  required String model,
  required String format,
  String? voice,
}) {
  final line = StringBuffer('tts: $model · $format');
  if (voice != null) line.write(' · $voice');
  return line.toString();
}

/// Beat 3 — the completion summary: the face's own measure.
String ttsCompletionLine({required int bytes, required Duration elapsed}) =>
    'tts: $bytes bytes · ${elapsed.inMilliseconds}ms';
