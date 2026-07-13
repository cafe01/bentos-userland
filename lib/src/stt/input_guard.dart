/// Resolves whether `stt` may read stdin (§5.4-3 — the stdin binary guard).
///
/// Pure decision, no device touched: audio is binary and never comes from a
/// keyboard (product-spec §3.3/§3.4), so — unlike `tts`'s text input — there
/// is no interactive read here, only refusal. [resolveSttInput] answers
/// before `TranscribeCommand`/`LiveCommand` opens anything, so a refusal
/// never wastes a boot.
library;

/// Which verb is asking — the two guards share the law but not the wording
/// (product-spec §3.3 vs §3.4).
enum SttInputKind { transcribe, live }

/// The outcome of sensing stdin against [SttInputKind]. Sealed so a caller's
/// `switch` is exhaustive.
sealed class SttInputResolution {
  const SttInputResolution();
}

/// stdin is a terminal — refused before the device opens. [message] is
/// `stderr`-ready.
final class SttInputRefused extends SttInputResolution {
  const SttInputRefused(this.message);
  final String message;
}

/// stdin is piped (or a positional/`-` source is present) — the job may
/// proceed.
final class SttInputAllowed extends SttInputResolution {
  const SttInputAllowed();
}

/// [stdinIsTerminal] is the sensed stream state — injected so the guard is
/// testable without a pty.
SttInputResolution resolveSttInput(
  SttInputKind kind, {
  required bool stdinIsTerminal,
}) {
  if (!stdinIsTerminal) return const SttInputAllowed();
  final hint = switch (kind) {
    SttInputKind.transcribe => 'pass a file (stt recording.wav) or pipe one',
    SttInputKind.live => 'pipe a live PCM source',
  };
  return SttInputRefused('stt: no audio on the terminal — $hint');
}
