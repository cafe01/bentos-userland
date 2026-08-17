import 'package:args/args.dart';

import 'program.dart';

const usage = '''
usage: mcp <program> [<fixed-arg>...] [--help-flag <flag>] [--name <tool-name>]

Presents one command-line program as one MCP tool, over stdio.

A program named alone is presented whole. Named with fixed arguments after
it, what is presented is that invocation — `mcp bentos-agent claude-spawn`
presents the subcommand, not the program that carries it. The fixed
arguments lead every call and the help probe alike; a caller's own
arguments follow them and can never displace them.

  --help-flag   where the tool description comes from (default: --help)
  --name        tool name, when the last word of the invocation will not do''';

/// `mcp`'s own options. Nothing here is ever passed into the presented
/// program: the surface carried is the program's own.
ArgParser buildParser() => ArgParser()
  ..addOption('help-flag', defaultsTo: '--help')
  ..addOption('name');

/// Reads the invocation and prepares the program it names. Throws
/// [StartupFailure] for a bad invocation, an unresolvable program, or a
/// program that prints no help — all of them before the server connects.
Future<Program> prepareFromArgs(List<String> args) async {
  final ArgResults parsed;
  try {
    parsed = buildParser().parse(args);
  } on FormatException catch (e) {
    throw StartupFailure('${e.message}\n\n$usage');
  }

  // One program still, and never none — but what follows it is the
  // invocation, not a second program. A subcommand is where most organs
  // actually live, and refusing the shape only moved the problem into a
  // wrapper script somebody else had to write and maintain.
  if (parsed.rest.isEmpty) {
    throw StartupFailure('no program named\n\n$usage');
  }

  return Program.prepare(
    parsed.rest.first,
    leading: parsed.rest.skip(1).toList(),
    helpFlag: parsed.option('help-flag')!,
    toolName: parsed.option('name'),
  );
}
