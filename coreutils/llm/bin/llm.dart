/// `llm` — the inert inference coreutil. Thin entrypoint: all logic lives in
/// [LlmRunner] and the command/domain layers under `lib/`.
library;

import 'dart:io';

import 'package:llm/llm.dart';

void main(List<String> args) async {
  // A piped stdin (not a TTY) lets a bare `echo … | llm` route to the prompt
  // command, which reads the prompt from stdin.
  exit(await LlmRunner().run(args, stdinHasPrompt: !stdin.hasTerminal));
}
