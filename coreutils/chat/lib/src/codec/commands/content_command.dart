/// `chat-codec content` — construct a ChatContent block and emit it as one JSONL line.
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
      'Construct a ChatContent block and emit it as a JSONL line on stdout.\n'
      'Currently supports --text. Multimodal is an open seam.';

  @override
  String get invocation => 'chat-codec content --text <text>';

  @override
  Future<int> run() async {
    final text = argResults!['text'] as String?;
    if (text == null) {
      throw UsageException('--text is required (the only supported type)', usage);
    }
    (out ?? stdout).writeln(encodeContentJson(TextContent(text)));
    return 0;
  }

  // Injectable for testing.
  StringSink? out;
}
