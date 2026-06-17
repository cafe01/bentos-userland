/// `chat-codec message` — construct a ChatMessage and emit it as one JSON line.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';

class MessageCommand extends Command<int> {
  MessageCommand() {
    argParser
      ..addOption(
        'user',
        abbr: 'u',
        help: 'Create a user message with this text.',
        valueHelp: 'text',
      )
      ..addOption(
        'system',
        abbr: 's',
        help: 'Create a system message with this text.',
        valueHelp: 'text',
      )
      ..addOption(
        'assistant',
        abbr: 'a',
        help: 'Create an assistant message with this text.',
        valueHelp: 'text',
      );
  }

  @override
  String get name => 'message';

  @override
  String get description =>
      'Construct a ChatMessage and emit it as one JSONL line on stdout.\n'
      'Exactly one of --user / --system / --assistant is required.';

  @override
  String get invocation =>
      'chat-codec message (--user | --system | --assistant) <text>';

  @override
  Future<int> run() async {
    final user = argResults!['user'] as String?;
    final system = argResults!['system'] as String?;
    final assistant = argResults!['assistant'] as String?;

    final set = [user, system, assistant].where((v) => v != null).length;
    if (set != 1) {
      throw UsageException(
        'exactly one of --user / --system / --assistant is required',
        usage,
      );
    }

    final ChatRole role;
    final String text;

    if (user != null) {
      role = ChatRole.user;
      text = user;
    } else if (system != null) {
      role = ChatRole.system;
      text = system;
    } else {
      role = ChatRole.assistant;
      text = assistant!;
    }

    final message = ChatMessage(role: role, content: [TextContent(text)]);
    (out ?? stdout).writeln(encodeMessageJson(message));
    return 0;
  }

  // Injectable for testing.
  StringSink? out;
}
