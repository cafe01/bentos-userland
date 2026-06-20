/// The `chat-render` coreutil's public library — the ChatEvent-JSONL→styled-text
/// filter, exposed so the renderer and its backends are testable from outside `bin/`.
library;

export 'src/chat-render/backend/render_backend.dart' show RenderBackend, StyleRole, GlyphName;
export 'src/chat-render/backend/ansi_backend.dart' show AnsiBackend;
export 'src/chat-render/backend/plain_backend.dart' show PlainBackend;
export 'src/chat-render/render_options.dart' show RenderOptions;
export 'src/chat-render/chat_renderer.dart' show ChatRenderer;
