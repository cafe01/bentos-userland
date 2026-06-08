/// `llm chat` — interactive REPL. Multi-turn context held in memory; each turn
/// streams its own answer. `/exit` or Ctrl-D quits. No disk, no history file —
/// the context dies with the process.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';

import 'llm_base_command.dart';

class ChatCommand extends LlmBaseCommand {
  @override
  String get name => 'chat';

  @override
  String get description =>
      'Interactive REPL: multi-turn context held in memory, one stream per '
      'turn. /exit or Ctrl-D quits. No persistence.';

  @override
  String get invocation =>
      'llm chat [-d <device>] [-s <system>]... [-t <n>] [--temperature <f>] [-v]';

  @override
  Future<int> run() async {
    final consumer = await bootConsumer();
    if (consumer == null) return 3;

    // The conversation grows in memory across turns — the whole of the context.
    final conversation = <ChatMessage>[];
    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();
      if (line == null) {
        stdout.writeln(); // tidy newline after a Ctrl-D
        break;
      }
      final input = line.trim();
      if (input == '/exit') break;
      if (input.isEmpty) continue; // blank line — re-prompt, never crash

      conversation.add(ChatMessage.userText(input));
      try {
        final reply = await consumer.streamTurn(
          conversation,
          systemMessages: systemMessages,
          config: ioConfig,
          verbose: verbose,
        );
        // Append the assistant's turn so the next turn sees it (RAM context).
        conversation.add(ChatMessage.assistantText(reply));
      } on BentosException catch (e) {
        // A POSIX/IO error from behind the device (e.g. EACCES with no key)
        // surfaces exactly as in single-shot — clean, then exit.
        stderr.writeln('llm: $e');
        return 1;
      }
    }
    return 0;
  }
}
