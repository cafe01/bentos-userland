/// The `.llm` session — one inference session as an entity, and the runner
/// that answers it.
///
/// The engine, not a face: `llm` at the shell and a graphical playground are
/// both views over this, and neither owns it.
library;

export 'src/llm_session/fold.dart';
export 'src/llm_session/live.dart';
export 'src/llm_session/runner.dart';
export 'src/llm_session/schema.dart';
export 'src/llm_session/session.dart';
export 'src/llm_session/watch.dart';
