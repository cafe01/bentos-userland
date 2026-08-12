import 'package:dart_mcp/server.dart';

import 'program.dart';
import 'version.dart';

/// An MCP server that presents exactly one command-line program as exactly one
/// tool. Everything about the protocol — framing, handshake, capability
/// negotiation, schema validation — comes from the floor.
final class ProgramServer extends MCPServer with ToolsSupport {
  ProgramServer(super.channel, {required this.program})
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'mcp/${program.name}',
          version: packageVersion,
        ),
        instructions:
            'Presents the command-line program `${program.name}` as one tool.',
      ) {
    registerTool(program.tool, program.call);
  }

  final Program program;

  @override
  Future<void> shutdown() async {
    await program.stopAll();
    await super.shutdown();
  }
}
