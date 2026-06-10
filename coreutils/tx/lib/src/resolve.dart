import 'dart:io';

/// Resolution errors carry an agent-facing message and exit non-zero.
final class TxResolveError extends Error {
  TxResolveError(this.message);
  final String message;
  @override
  String toString() => 'tx: $message';
}

/// The entity whose log a `tx` operation references.
///
/// `entity = --agent <name> ?? $BENTOS_AGENT`. There is no fallback to the
/// operator: a human in a raw shell must *name* the being. The operator
/// ($USER) is never an entity — `tx` never writes a log for them.
String resolveEntity(String? agentFlag, Map<String, String> environment) {
  final agent = agentFlag ?? environment['BENTOS_AGENT'];
  if (agent == null || agent.isEmpty) {
    throw TxResolveError(
      'no entity. Pass --agent <name> or set \$BENTOS_AGENT. '
      'A being owns the log; the operator never does.',
    );
  }
  return agent;
}

/// Resolves the place root by walking up from [start] for the governing
/// `place.yaml` — the same hierarchy `.mem` uses. The entity's repo roots
/// there, so `.tx/<entity>/` and `.mem/<entity>/` always land together.
///
/// `<place>` is NOT the literal CWD; rooting at CWD would scatter `.tx/`
/// across every directory a turn runs in.
Directory resolvePlaceRoot(Directory start) {
  var dir = start.absolute;
  while (true) {
    if (File('${dir.path}/place.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw TxResolveError(
        'no place.yaml found walking up from ${start.path}. '
        '`tx` roots the log at the governing place, like `.mem`.',
      );
    }
    dir = parent;
  }
}

/// The repo directory for [entity] at the place governing [start]:
/// `<placeRoot>/.tx/<entity>/`.
Directory resolveRepoDir(String entity, Directory start) {
  final placeRoot = resolvePlaceRoot(start);
  return Directory('${placeRoot.path}/.tx/$entity');
}
