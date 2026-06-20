/// `chat-codec fold` — reduce a ChatEvent JSONL stream into a ChatMessage.
///
/// Reads ChatEvent JSON lines from stdin, folds them into the assembled
/// assistant ChatMessage (via foldToMessage()), and emits one JSONL line on
/// stdout. This is the downstream transformer for `llm --output-format jsonl`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chat_inference/chat_inference.dart';

class FoldCommand extends Command<int> {
  @override
  String get name => 'fold';

  @override
  String get description =>
      'Reduce a ChatEvent JSONL stream (stdin) into the assembled ChatMessage '
      'and emit it as one JSONL line on stdout.\n'
      'Usage: llm … | chat-codec fold >> messages.jsonl';

  @override
  String get invocation => 'llm … | chat-codec fold';

  @override
  Future<int> run() async {
    if (stdin.hasTerminal) {
      throw UsageException(
        'fold reads from a piped stdin (no terminal)',
        usage,
      );
    }

    final controller = StreamController<ChatEvent>();

    final feedFuture = stdin
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .forEach((line) {
      try {
        controller.add(decodeEventJson(line));
      } catch (e) {
        controller.addError(
          FormatException('chat-codec fold: malformed event line — $e'),
        );
      }
    }).whenComplete(controller.close);

    try {
      final message = await controller.stream.foldToMessage();
      stdout.writeln(encodeMessageJson(message));
      await feedFuture;
    } on FormatException catch (e) {
      stderr.writeln('$e');
      return 64;
    } catch (e) {
      stderr.writeln('chat-codec fold: $e');
      return 1;
    }
    return 0;
  }
}
