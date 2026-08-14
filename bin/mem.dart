import 'dart:io';

import 'package:bentos_userland/mem.dart';
import 'package:bentos_userland/src/mem_llm/gist_seam.dart';

final class _StdSink implements Sink<String> {
  const _StdSink(this._sink);
  final IOSink _sink;
  @override
  void add(String data) => _sink.write(data);
  @override
  void close() {}
}

Future<void> main(List<String> args) async {
  // A silent success is the one failure a memory organ must never have, and a
  // Dart VM whose event loop drains exits 0 by default — so the failing code
  // is armed up front and disarmed only by reaching the `exit` below.
  exitCode = 70;

  // Stdin is handed over as a reader, never drained up front: only a write
  // without --file wants a body, and a read verb must never block on a stdin
  // that an inherited pipe holds open forever. The TTY guard stays — an
  // interactive `mem remember topic` fails on a missing body instead of
  // waiting for an EOF that won't come.
  final mem = Mem(
    vantage: Directory.current.path,
    out: _StdSink(stdout),
    diagnostics: _StdSink(stderr),
    environment: Platform.environment,
    stdinReader: stdin.hasTerminal
        ? null
        : () => stdin.transform(const SystemEncoding().decoder).join(),
    fileReader: (path) => File(path).readAsString(),
    gistSource: const LlmGistSource(),
  );
  exit(await mem.call(args));
}
