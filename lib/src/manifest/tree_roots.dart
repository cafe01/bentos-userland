import 'dart:io';

/// Reads BENTOS_TREE_PATH (colon-separated) and returns the list of tree roots.
/// Returns an empty list when the variable is absent or empty.
List<String> resolveTreeRoots() {
  final raw = Platform.environment['BENTOS_TREE_PATH'] ?? '';
  if (raw.isEmpty) return const [];
  return raw.split(':').where((s) => s.isNotEmpty).toList();
}
