/// Entity → tx repo resolution, shared by every session-aware command.
///
/// chatbot's persistence is the SAME tx substrate every userland program
/// shares — no bespoke session store. The old `$XDG_DATA_HOME/chatbot/sessions`
/// JSONL store is gone; a being's conversation lives in `<place>/.tx/<entity>/`,
/// beside its `.mem/`.
library;

import 'dart:io';

import 'package:tx/tx.dart';

/// Resolves the entity (`--agent ?? $BENTOS_AGENT`) and returns its tx repo,
/// rooted at the governing place (mirrors `.mem`). Throws [TxResolveError] when
/// no being is named.
TxRepo openRepoForAgent(String? agentFlag) {
  final entity = resolveEntity(agentFlag, Platform.environment);
  return TxRepo(resolveRepoDir(entity, Directory.current), entity);
}
