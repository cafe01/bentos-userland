import 'dart:io';

import 'package:bentos_userland/mem2.dart';

Future<void> main(List<String> args) async {
  // Drain a real pipe up front — only when stdin isn't a TTY, so an
  // interactive invocation with no body (e.g. `mem remember topic`,
  // expecting --file) never blocks waiting for an EOF that won't come.
  final stdinContent = stdin.hasTerminal
      ? null
      : await stdin.transform(const SystemEncoding().decoder).join();
  final runner = MemRunner(stdinContent: stdinContent);
  await runner.run(args);
  exit(runner.exitCode);
}
