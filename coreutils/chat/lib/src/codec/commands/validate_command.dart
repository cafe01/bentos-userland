/// `chat-codec validate` — validate a ChatEvent JSONL stream from stdin.
///
/// Each non-empty line must decode as a valid ChatEvent (proto3 JSON).
/// Exits 0 if all lines are valid; 1 if any line fails.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat.dart';

class ValidateCommand extends Command<int> {
  @override
  String get name => 'validate';

  @override
  String get description =>
      'Read a ChatEvent JSONL stream from stdin and validate each line. '
      'Exits 0 if all lines are valid ChatEvents; exits 1 on first error.';

  @override
  String get invocation => 'llm … | chat-codec validate';

  @override
  Future<int> run() async {
    var lineNum = 0;
    var errors = 0;

    await for (final line in stdin
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())) {
      lineNum++;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        decodeEventJson(trimmed);
      } catch (e) {
        stderr.writeln('chat-codec validate: line $lineNum: $e');
        errors++;
      }
    }

    if (errors > 0) {
      stderr.writeln('chat-codec validate: $errors error(s) in $lineNum line(s)');
      return 1;
    }
    return 0;
  }
}
