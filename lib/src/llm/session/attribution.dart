/// The attribution rule: who a person understands to have spoken.
///
/// Read off what the message *carries*, never off the role it travels under. A
/// function result rides as a `user`-role message because that is what the wire
/// says; printing it raw puts words in a person's mouth that they never typed.
library;

import 'package:chat_inference/chat_inference.dart';

import 'transcript.dart';

final class SpeakerRule implements Attribution {
  const SpeakerRule();

  @override
  Speaker of(ChatMessage message) => switch (message.role) {
        ChatRole.system => Speaker.constitution,
        ChatRole.assistant => Speaker.agent,
        // The one rule that is not the role: a result carried under the user's
        // role is the executor's, whatever else travels beside it.
        ChatRole.user => message.content.any((c) => c is FunctionResultContent)
            ? Speaker.executor
            : Speaker.you,
      };
}
