/// `llm <prompt>` — the default command: stream one answer and exit.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';

import 'llm_base_command.dart';

class PromptCommand extends LlmBaseCommand {
  @override
  String get name => 'prompt';

  @override
  String get description =>
      'Stream one answer and exit (the default command). With no prompt arg '
      'and piped stdin, the prompt is read from stdin.';

  @override
  String get invocation => 'llm [-v] [-d <device>] <prompt>   (or: echo … | llm)';

  @override
  Future<int> run() async {
    final consumer = bootConsumer();
    if (consumer == null) return 3;

    final prompt = await _resolvePrompt(argResults!.rest);
    if (prompt == null || prompt.trim().isEmpty) {
      throw UsageException('a prompt is required', usage);
    }

    try {
      await consumer.streamTurn([ChatMessage.userText(prompt)], verbose: verbose);
    } on BentosException catch (e) {
      stderr.writeln('llm: $e');
      return 1;
    }
    return 0;
  }

  /// The prompt is the joined positional args, or — if there are none and stdin
  /// is piped — the whole of stdin.
  Future<String?> _resolvePrompt(List<String> rest) async {
    if (rest.isNotEmpty) return rest.join(' ');
    if (stdin.hasTerminal) return null;
    return (await stdin.transform(systemEncoding.decoder).join()).trim();
  }
}
