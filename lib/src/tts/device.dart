/// Device-path resolution for `tts` — the precedence that turns a bare `tts`
/// into a concrete `/dev/tts/<vendor>/<model>` path.
///
/// The TTS subsystem carries one device class (§1.2), so there is no protocol
/// segment and no verb append — the `stt` twin's `withVerb` has no counterpart
/// here. The genus stays open (§1.2: a future `LiveSpeechSynthesis` would add a
/// segment), so the shape mirrors `stt/device.dart` deliberately.
library;

/// The device used when neither `--device` nor [ttsDeviceEnvVar] is given.
/// Points at provider/model — the whole path for this one-class subsystem.
const defaultTtsDevice = '/dev/tts/openai/tts-1';

/// The environment variable that overrides [defaultTtsDevice].
const ttsDeviceEnvVar = 'BENTOS_TTS_DEVICE';

/// Coreutil version — printed by `tts --version`.
const ttsVersion = '0.1.0';

/// Normalises a user-supplied device string to a `/dev/tts/…` path.
String normalizeTtsDevice(String path) =>
    path.startsWith('/') ? path : '/dev/tts/$path';

/// Resolves the device in precedence order: [explicit] (`--device`), then
/// [ttsDeviceEnvVar] in [environment], then [defaultTtsDevice]. [environment]
/// is injectable for tests.
String resolveTtsDevice(
  String? explicit, {
  Map<String, String> environment = const {},
}) {
  if (explicit != null && explicit.isNotEmpty) {
    return normalizeTtsDevice(explicit);
  }
  final fromEnv = environment[ttsDeviceEnvVar];
  if (fromEnv != null && fromEnv.isNotEmpty) return normalizeTtsDevice(fromEnv);
  return defaultTtsDevice;
}
