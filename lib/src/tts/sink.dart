/// Resolves the payload sink for `tts` (§5.4-4 — the stdout binary guard).
///
/// Pure decision, no device touched: [resolveTtsSink] answers *where the
/// audio goes* before `SynthesizeCommand` opens anything, so a refusal never
/// wastes a synthesis job.
library;

import 'dart:io';

/// The outcome of resolving `-o`/`--output` against the stdout-terminal
/// sense (§1.1/§5.4-4). Sealed so a caller's `switch` is exhaustive.
sealed class TtsSinkResolution {
  const TtsSinkResolution();
}

/// stdout is a terminal, no `-o` was given, and the payload is binary audio —
/// refused before the device opens. [message] is `stderr`-ready.
final class TtsSinkRefused extends TtsSinkResolution {
  const TtsSinkRefused(this.message);
  final String message;
}

/// The resolved sink: [file] is the `-o <path>` target, or `null` for stdout
/// (either no `-o` with stdout piped, or the `-o -` escape hatch).
final class TtsSinkResolved extends TtsSinkResolution {
  const TtsSinkResolved(this.file);
  final File? file;
}

/// [output] is the raw `--output` value (`null` if absent, `'-'` for the
/// explicit-stdout convention, else a file path). [stdoutIsTerminal] is the
/// sensed stream state — injected so the guard is testable without a pty.
TtsSinkResolution resolveTtsSink(
  String? output, {
  required bool stdoutIsTerminal,
}) {
  if (output == null) {
    if (stdoutIsTerminal) {
      return const TtsSinkRefused(
        'tts: refusing to write audio to a terminal — use -o <file> or redirect',
      );
    }
    return const TtsSinkResolved(null);
  }
  if (output == '-') return const TtsSinkResolved(null);
  return TtsSinkResolved(File(output));
}
