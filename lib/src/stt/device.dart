/// Device-path resolution for `stt` — the precedence that turns a bare `stt`
/// into a concrete `/dev/stt/<vendor>/<model>` path, plus the verb → protocol
/// segment append (§5.4 seam 3).
library;

/// The device used when neither `--device` nor [sttDeviceEnvVar] is given.
/// Points at provider/model only — never the protocol segment (§1.1); the verb
/// appends that.
const defaultSttDevice = '/dev/stt/openai/whisper-1';

/// The environment variable that overrides [defaultSttDevice].
const sttDeviceEnvVar = 'BENTOS_STT_DEVICE';

/// Coreutil version — printed by `stt --version`.
const sttVersion = '0.1.0';

/// Normalises a user-supplied device string to a `/dev/stt/…` base (no verb).
String normalizeSttDevice(String path) =>
    path.startsWith('/') ? path : '/dev/stt/$path';

/// Resolves the device base in precedence order: [explicit] (`--device`), then
/// [sttDeviceEnvVar] in [environment], then [defaultSttDevice]. The base is
/// `<vendor>/<model>` only; `--device` never carries the protocol (§1.1).
/// [environment] is injectable for tests.
String resolveSttDevice(
  String? explicit, {
  Map<String, String> environment = const {},
}) {
  if (explicit != null && explicit.isNotEmpty) {
    return normalizeSttDevice(explicit);
  }
  final fromEnv = environment[sttDeviceEnvVar];
  if (fromEnv != null && fromEnv.isNotEmpty) return normalizeSttDevice(fromEnv);
  return defaultSttDevice;
}

/// Appends the protocol-segment [verb] (§5.4 seam 3) — the coreutil maps its
/// verb onto the device path; the base [deviceBase] never carries the protocol.
String withVerb(String deviceBase, String verb) => '$deviceBase/$verb';
