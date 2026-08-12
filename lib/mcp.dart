/// The `mcp` coreutil's public library — one command-line program presented as
/// one MCP tool. Exposed so the server and its startup are testable from
/// outside `bin/`.
library;

export 'src/mcp/program.dart';
export 'src/mcp/program_server.dart';
export 'src/mcp/startup.dart';
export 'src/mcp/version.dart';
