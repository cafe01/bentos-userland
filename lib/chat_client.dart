/// `chat` — the program a person lives in, over `bentos.chat`.
///
/// The client's own core: a session of rooms, the loop that drives them, and
/// the one component allowed to say `nocterm`. What the medium is made of
/// lives one library over, in `bentos_chat.dart`.
library;

export 'src/chat_client/app.dart';
export 'src/chat_client/hotlist.dart';
export 'src/chat_client/input.dart';
export 'src/chat_client/intent.dart';
export 'src/chat_client/persisted_state.dart';
export 'src/chat_client/render/screen_view.dart';
export 'src/chat_client/room.dart';
export 'src/chat_client/screen_model.dart';
export 'src/chat_client/session.dart';
export 'src/chat_client/ticker.dart';
export 'src/chat_client/transcript.dart';
