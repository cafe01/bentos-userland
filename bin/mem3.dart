// bin/mem3.dart — temporary executable over the greenfield build (Café's
// ruling: exercise the new domain in isolation before the real `mem` cuts
// over to it). Deleted at cutover; `mem2.dart` remains what `bin/mem.dart`
// wires until then.

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
