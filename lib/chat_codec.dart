/// The `chat-codec` coreutil's public library — the ChatInference data model as a
/// CLI codec. Exposed so the runner and its commands are testable from outside `bin/`.
library;

export 'src/chat-codec/chat_codec_runner.dart';
export 'src/chat-codec/commands/content_command.dart';
export 'src/chat-codec/commands/event_command.dart';
export 'src/chat-codec/commands/fold_command.dart';
export 'src/chat-codec/commands/message_command.dart';
export 'src/chat-codec/commands/validate_command.dart';
