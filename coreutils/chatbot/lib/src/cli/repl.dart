/// The species loop — the `while` between turns.
///
/// This is what makes `chatbot` a SPECIES and not a coreutil: it owns the loop
/// (the loop-ownership test). `chat` is one turn (`bash -c`); `chatbot` loops
/// turns (`bash -i`). But even the species is the loop over the SAME turn
/// machinery (`Turn`) and the SAME persistence seam (`ChatSession`) — it does
/// not re-implement them.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:chat/chat.dart';

/// Reads stdin turn by turn, recording each user input (write-ahead) and
/// running one [turn] per line until `/exit` or EOF. The turn persists the
/// assistant + tool messages itself via the [session] sink.
Future<int> runRepl({
  required ChatSession session,
  required Turn turn,
  required List<ChatMessage> conversation,
}) async {
  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync();
    if (line == null) {
      stdout.writeln();
      break;
    }
    final input = line.trim();
    if (input == '/exit') break;
    if (input.isEmpty) continue;

    final userMsg = ChatMessage.userText(input);
    await session.record(userMsg); // write-ahead: input commits before inference
    conversation.add(userMsg);

    try {
      await turn.run(conversation);
    } on BentosException catch (e) {
      stderr.writeln('chatbot: $e');
      return 1;
    }
  }
  return 0;
}
