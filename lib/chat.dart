/// The chat subsystem header — the stdlib's `sys/chat.h` (architecture §5):
/// `ChatDevice` over the `Bentos` surface. The core layer (`bentos_userland.dart`)
/// never hears of these types; they are payload to it.
library;

export 'package:chat_inference/chat_inference.dart';

export 'src/llm/bentos_chat_device.dart';
export 'src/llm/chat_ioctl_cmds.dart';
