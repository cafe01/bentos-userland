import 'package:args/args.dart';

import 'program.dart';

const usage = '''
usage: mcp <program> [--help-flag <flag>] [--name <tool-name>]

Presents one command-line program as one MCP tool, over stdio.

  --help-flag   where the tool description comes from (default: --help)
  --name        tool name, when the program's basename will not do''';

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

  // Exactly one program: there is no way to present two, and no way to
  // present none.
  if (parsed.rest.isEmpty) {
    throw StartupFailure('no program named\n\n$usage');
  }
  if (parsed.rest.length > 1) {
    throw StartupFailure(
      'one invocation presents one program, got ${parsed.rest.length}: '
      '${parsed.rest.join(' ')}\n\n$usage',
    );
  }

  return Program.prepare(
    parsed.rest.single,
    helpFlag: parsed.option('help-flag')!,
    toolName: parsed.option('name'),
  );
}
