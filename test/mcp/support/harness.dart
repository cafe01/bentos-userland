import 'dart:async';

import 'package:bentos_userland/mcp.dart';
import 'package:dart_mcp/client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// The suite is run from the package root.
const fixtureProgram = 'test/mcp/fixtures/program';
const helplessProgram = 'test/mcp/fixtures/helpless';

/// The server is exercised through `dart_mcp`'s own client over an in-memory
/// channel, so the handshake, the listing and the calls are proven as a client
/// sees them.
class ServerHarness {
  ServerHarness(Program program) {
    server = ProgramServer(serverChannel, program: program);
    connection = client.connectServer(clientChannel);
    addTearDown(shutdown);
  }

  final _clientController = StreamController<String>();
  final _serverController = StreamController<String>();

  late final clientChannel = StreamChannel<String>.withCloseGuarantee(
    _serverController.stream,
    _clientController.sink,
  );
  late final serverChannel = StreamChannel<String>.withCloseGuarantee(
    _clientController.stream,
    _serverController.sink,
  );

  final client = _HarnessClient();
  late final ProgramServer server;
  late final ServerConnection connection;

  Future<InitializeResult> initialize() async {
    final result = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    await server.initialized;
    return result;
  }

  Future<void> shutdown() async {
    await client.shutdown();
    await server.shutdown();
  }
}

base class _HarnessClient extends MCPClient {
  _HarnessClient()
    : super(Implementation(name: 'mcp test client', version: '0.1.0'));
}

/// Opens a harness on the fixture program, already past the handshake.
Future<ServerHarness> connectedToFixture({
  String program = fixtureProgram,
  List<String> leading = const [],
  String? name,
  String helpFlag = '--help',
}) async {
  final harness = ServerHarness(
    await Program.prepare(
      program,
      leading: leading,
      helpFlag: helpFlag,
      toolName: name,
    ),
  );
  await harness.initialize();
  return harness;
}

/// The text of the three parts a call always returns, in order: exit status,
/// stdout, stderr.
List<String> partsOf(CallToolResult result) =>
    [for (final content in result.content) (content as TextContent).text];
