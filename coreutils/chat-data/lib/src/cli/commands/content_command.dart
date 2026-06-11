/// `chat-data content` — construct a single ChatContent block as JSONL.
///
/// Currently supports text content only. Multimodal (binary, function-call,
/// function-result, thinking) is an open seam — see README.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';

class ContentCommand extends Command<int> {
  ContentCommand() {
    argParser.addOption(
      'text',
      abbr: 't',
      help: 'Construct a TextContent block with this text.',
      valueHelp: 'text',
    );
  }

  @override
  String get name => 'content';

  @override
  String get description =>
      'Construct a ChatContent block and emit it as a JSONL fragment.\n'
      'Currently supports --text. Multimodal is an open seam.';

  @override
  String get invocation => 'chat-data content --text <text>';

  @override
  Future<int> run() async {
    final text = argResults!['text'] as String?;
    if (text == null) {
      throw UsageException('--text is required (the only supported type)', usage);
    }
    // Emit as a standalone TextContent within a minimal assistant message
    // so the output is valid JSONL for downstream consumers.
    final message = ChatMessage(
      role: ChatRole.assistant,
      content: [TextContent(text)],
    );
    stdout.writeln(encodeMessageJson(message));
    return 0;
  }
}
