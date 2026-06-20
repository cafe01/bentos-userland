import 'dart:io';

export 'git.dart' show TxGitError;

/// Resolution errors carry an agent-facing message and exit non-zero.
final class TxResolveError extends Error {
  TxResolveError(this.message);
  final String message;
  @override
  String toString() => 'tx: $message';
}

/// The entity whose state a `tx` operation references.
///
/// `entity = --entity <name> ?? --agent <name> ?? $BENTOS_AGENT`.
/// No fallback to the operator — a human in a raw shell must name the entity.
String resolveEntity({
  String? entityFlag,
  String? agentFlag,
  required Map<String, String> environment,
}) {
  final name = entityFlag ?? agentFlag ?? environment['BENTOS_AGENT'];
  if (name == null || name.isEmpty) {
    throw TxResolveError(
      'no entity. Pass --entity <name> (or --agent <name>) or set '
      r'$BENTOS_AGENT. A being owns the state; the operator never does.',
    );
  }
  return name;
}

/// Walk up from [start] to the governing `place.yaml` — same hierarchy as
/// `.mem`. Returns the place root directory.
Directory resolvePlaceRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File('${dir.path}/place.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw TxResolveError(
        'no place.yaml found walking up from ${start.path}. '
        '`tx` roots state at the governing place, like `.mem`.',
      );
    }
    dir = parent;
  }
}

/// The scope directory: `<placeRoot>/.tx/<entity>/<scope>/`.
Directory resolveScopeDir(
  String entity,
  String scope,
  Directory start,
) {
  final placeRoot = resolvePlaceRoot(start);
  return Directory('${placeRoot.path}/.tx/$entity/$scope');
}

/// The entity root: `<placeRoot>/.tx/<entity>/`.
Directory resolveEntityDir(String entity, Directory start) {
  final placeRoot = resolvePlaceRoot(start);
  return Directory('${placeRoot.path}/.tx/$entity');
}

/// Infer (scope, thread) from [cwd] being inside a tx worktree.
///
/// Matches `<placeRoot>/.tx/<entity>/<scope>/<thread>/…` and returns
/// the (scope, thread) pair. Returns null if CWD is outside any worktree
/// for this entity.
({String scope, String thread})? resolveFromCwd(
  String entity,
  Directory placeRoot,
  Directory cwd,
) {
  final txBase = '${placeRoot.path}/.tx/$entity/';
  final absPath = '${cwd.absolute.path}/';
  if (!absPath.startsWith(txBase)) return null;
  final rel = absPath.substring(txBase.length);
  final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  return (scope: parts[0], thread: parts[1]);
}
