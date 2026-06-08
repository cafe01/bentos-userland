/// Device-path resolution — the precedence that turns a bare `llm` into a
/// concrete `/dev/llm/<vendor>/<model>` path.
library;

import 'config.dart';

/// Resolves the device path from the three sources, in precedence order:
///
/// 1. [explicit] — an explicit `--device` argument (highest priority);
/// 2. the [deviceEnvVar] environment variable;
/// 3. [defaultDevicePath].
///
/// [environment] defaults to the process environment; injectable for tests.
String resolveDevicePath(
  String? explicit, {
  Map<String, String> environment = const {},
}) {
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final fromEnv = environment[deviceEnvVar];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  return defaultDevicePath;
}
