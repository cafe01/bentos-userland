/// Coreutil configuration — the single piece the `llm` spec keeps (§2): a
/// default device so bare `llm "…"` works without typing the FQDN.
///
/// It is a path string, never a key or a driver — naming it here keeps the
/// commands free of magic constants and gives the one knob a home to grow into
/// (a config file, aliases) without touching command code.
library;

/// The device used when neither `--device` nor `BENTOS_LLM_DEVICE` is given.
const defaultDevicePath = '/dev/llm/openai/gpt-4o-mini';

/// The environment variable that overrides [defaultDevicePath].
const deviceEnvVar = 'BENTOS_LLM_DEVICE';

/// Devices the bootstrap knows about — the static cap-map wired in [boot.dart].
///
/// The ontologically correct enumeration is `ls /dev/llm/` (VFS readdir over
/// the cap namespace), but the kernel cannot list its device namespace yet.
/// [ModelsCommand] exposes this set as a stopgap so the gap is never silently
/// forgotten. Remove or replace with a real readdir when the kernel grows it.
const knownDevices = [
  '/dev/llm/anthropic/claude-sonnet-4',
  '/dev/llm/openai/gpt-4o-mini',
];
