/// `bentos.chat` — the medium, from the outside.
///
/// A conversation between participants: a channel they join, speak into, and
/// leave. It holds what was said and does nothing else — it computes nothing,
/// owes nothing, and has no opinion about who should speak next.
///
/// The library name is the entity's, not `chat.dart`: that one is the
/// inference device of the old face, which squats the medium's name and dies in
/// the commit where this covers it.
library;

export 'src/chat/channel.dart';
export 'src/chat/cli/chat_runner.dart';
export 'src/chat/cli/coordinate.dart';
export 'src/chat/cli/floor.dart';
export 'src/chat/cli/render.dart';
export 'src/chat/construction.dart';
export 'src/chat/entity_seams.dart';
export 'src/chat/handle.dart';
export 'src/chat/local_channel.dart';
export 'src/chat/model.dart';
export 'src/chat/outcome.dart';
export 'src/chat/seams.dart';
