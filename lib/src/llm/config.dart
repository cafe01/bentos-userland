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

/// Devices the bootstrap knows about — the paths a distribution's boot table
/// can route, loopback included.
///
/// The ontologically correct enumeration is `ls /dev/llm/` (VFS readdir over
/// the cap namespace), but the kernel cannot list its device namespace yet, so
/// the list is written here and read by everyone through `DeviceCatalog`.
/// Remove or replace with a real readdir when the kernel grows it.
///
/// Only the *names* are here. What each device can do is the device's own word,
/// read from it by ioctl — never a table beside this one.
const knownDevices = [
  '/dev/llm/anthropic/claude-sonnet-4',
  '/dev/llm/openai/gpt-4o-mini',
  '/dev/llm/fixture/weather',
  '/dev/llm/fixture/two-cities',
  '/dev/llm/fixture/echo',
];
