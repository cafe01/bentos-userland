/// Device-path resolution — the precedence that turns a bare `llm` into a
/// concrete `/dev/llm/<vendor>/<model>` path.
library;

import 'config.dart';
import 'llm_config.dart';

/// Normalises a user-supplied device string to a full `/dev/llm/…` path.
/// Accepts both `vendor/model` (short) and `/dev/llm/vendor/model` (full).
String normalizeDevicePath(String path) =>
    path.startsWith('/') ? path : '/dev/llm/$path';

/// Resolves the device path in precedence order:
///
/// 1. [explicit] — the `--device` argument, alias-resolved then normalised.
/// 2. [deviceEnvVar] in [environment], normalised.
/// 3. [config].defaultDevice — the user's configured default.
/// 4. [defaultDevicePath] — the built-in fallback.
///
/// [config] may be null; alias lookup and configured default are skipped
/// when it is. [environment] is injectable for tests.
String resolveDevicePath(
  String? explicit, {
  Map<String, String> environment = const {},
  LlmConfig? config,
}) {
  if (explicit != null && explicit.isNotEmpty) {
    final aliased = config?.aliases[explicit];
    if (aliased != null) return aliased;
    return normalizeDevicePath(explicit);
  }
  final fromEnv = environment[deviceEnvVar];
  if (fromEnv != null && fromEnv.isNotEmpty) return normalizeDevicePath(fromEnv);
  if (config?.defaultDevice != null) return config!.defaultDevice!;
  return defaultDevicePath;
}
