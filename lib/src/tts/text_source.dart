/// Resolves where `tts`'s text payload comes from (§1.1/§4.2/§5.4-3 — the
/// stdin interactive-read law).
///
/// Pure decision, no device touched: [resolveTtsTextSource] answers which of
/// the three sources feeds the job before `SynthesizeCommand` opens anything.
/// Positional beats piped stdin (explicit beats implicit, product-spec fork
/// #9); with neither, a terminal on stdin means a human is present with no
/// artifact to pipe, so the face reads the keyboard interactively instead of
/// refusing (the text twin of `stt`'s binary refusal, §5.4-3).
library;

import 'dart:convert';

/// The outcome of resolving the text source. Sealed so a caller's `switch`
/// is exhaustive.
sealed class TtsTextSourceResolution {
  const TtsTextSourceResolution();
}

/// The positional argument carries the text — wins over piped stdin.
final class TtsTextSourcePositional extends TtsTextSourceResolution {
  const TtsTextSourcePositional(this.text);
  final String text;
}

/// stdin is piped — the payload is the pipe (the working pipe case).
final class TtsTextSourceStdin extends TtsTextSourceResolution {
  const TtsTextSourceStdin();
}

/// No positional, stdin is a terminal — read the keyboard to Ctrl-D.
final class TtsTextSourceInteractive extends TtsTextSourceResolution {
  const TtsTextSourceInteractive();
}

/// [positional] is the joined positional argument (`null` if absent).
/// [stdinIsTerminal] is the sensed stream state — injected so the guard is
/// testable without a pty.
TtsTextSourceResolution resolveTtsTextSource(
  String? positional, {
  required bool stdinIsTerminal,
}) {
  if (positional != null) return TtsTextSourcePositional(positional);
  if (!stdinIsTerminal) return const TtsTextSourceStdin();
  return const TtsTextSourceInteractive();
}

/// Collects [keystrokes] to EOF (Ctrl-D) and decodes them as UTF-8 text —
/// the accumulation half of the interactive read. An empty stream (immediate
/// Ctrl-D) decodes to an empty string; the caller maps that to `EX_USAGE`
/// (§4.2 — a clean usage error, not an empty job).
Future<String> readInteractiveText(Stream<List<int>> keystrokes) async {
  final buffer = StringBuffer();
  await for (final chunk in keystrokes.transform(utf8.decoder)) {
    buffer.write(chunk);
  }
  return buffer.toString();
}
