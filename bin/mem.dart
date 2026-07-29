import 'dart:io';

import 'package:bentos_userland/mem2.dart';

Future<void> main(List<String> args) async {
  // Stdin is handed over as a reader, never drained up front: only `remember`
  // without --file wants a body, and a read verb must never block on a stdin
  // that an inherited pipe holds open forever. The TTY guard stays — an
  // interactive `mem remember topic` fails on a missing body instead of
  // waiting for an EOF that won't come.
  final runner = MemRunner(
    stdinReader: stdin.hasTerminal
        ? null
        : () => stdin.transform(const SystemEncoding().decoder).join(),
  );
  await runner.run(args);
  exit(runner.exitCode);
}
