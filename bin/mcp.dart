import 'dart:io' as io;

import 'package:bentos_userland/mcp.dart';
import 'package:dart_mcp/stdio.dart';

/// Stdout is the wire. Every diagnostic of ours goes to stderr, and nothing in
/// this process may `print`.
Future<void> main(List<String> args) async {
  final Program program;
  try {
    program = await prepareFromArgs(args);
  } on StartupFailure catch (failure) {
    io.stderr.writeln('mcp: ${failure.message}');
    io.exit(2);
  }

  final server = ProgramServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    program: program,
  );
  await server.done;
  io.exit(0);
}
