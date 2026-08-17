import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  group('the listing', () {
    test('shows one tool, named for the program, described by its help',
        () async {
      final harness = await connectedToFixture();

      final tools = (await harness.connection.listTools()).tools;

      expect(tools, hasLength(1));
      expect(tools.single.name, 'program');
      expect(
        tools.single.description,
        contains('fixture — a program with knowable behaviour'),
      );
    });

    test('takes the description from another flag when told to', () async {
      final harness = await connectedToFixture(helpFlag: '--usage');

      final tools = (await harness.connection.listTools()).tools;

      expect(
        tools.single.description,
        contains('described from behind another flag'),
      );
    });

    test('takes the tool name from --name when given', () async {
      final harness = await connectedToFixture(name: 'fixture-under-a-name');

      final tools = (await harness.connection.listTools()).tools;

      expect(tools.single.name, 'fixture-under-a-name');
    });

    test('declares args, stdin and timeout, none of them required', () async {
      final harness = await connectedToFixture();

      final schema = (await harness.connection.listTools()).tools.single
          .inputSchema;

      expect(schema.properties!.keys, containsAll(['args', 'stdin', 'timeout']));
      expect(schema.required ?? const [], isEmpty);
    });
  });

  group('a presented subcommand', () {
    test('is described by the subcommand, and its args follow the fixed ones',
        () async {
      final harness = await connectedToFixture(leading: ['sub'], name: 'sub');

      final tools = (await harness.connection.listTools()).tools;
      expect(tools.single.description, contains('fixture sub —'));

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'sub',
          arguments: {
            'args': ['one', 'two three'],
          },
        ),
      );

      // The caller never says 'sub' and cannot say it differently: the fixed
      // arguments lead, and a caller's own follow. A tool that let the caller
      // reach the program's other subcommands would be presenting the program.
      expect(partsOf(result)[1], 'stdout:\nsub saw: one two three\n');
    });
  });

  group('a call', () {
    test('with args returns them', () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['echo-args', 'one', 'two three'],
          },
        ),
      );

      expect(result.isError, isNot(true));
      expect(partsOf(result)[1], 'stdout:\none\ntwo three\n');
    });

    test('with stdin returns it', () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['echo-stdin'],
            'stdin': 'spoken into the program\n',
          },
        ),
      );

      expect(partsOf(result)[1], 'stdout:\nspoken into the program\n');
    });

    test('with neither runs the program bare', () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(name: 'program'),
      );

      expect(result.isError, isNot(true));
      expect(partsOf(result)[1], 'stdout:\nbare\n');
    });

    test('returns the three parts apart, empty ones stated', () async {
      final harness = await connectedToFixture();

      final both = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['both'],
          },
        ),
      );

      expect(partsOf(both), [
        'exit status: 0',
        'stdout:\nto stdout\n',
        'stderr:\nto stderr\n',
      ]);

      final bare = await harness.connection.callTool(
        CallToolRequest(name: 'program'),
      );

      expect(partsOf(bare)[2], 'stderr: (empty)');
    });

    test('exit 0 is not an error', () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['exit', '0'],
          },
        ),
      );

      expect(result.isError, isNot(true));
    });

    test('a non-zero exit is an error carrying the program\'s own account',
        () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['exit', '7'],
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(partsOf(result)[0], contains('7'));
      expect(partsOf(result)[1], contains('leaving with 7'));
    });

    test('an expired bound is an error carrying what was written first',
        () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['slow', '30'],
            'timeout': 500,
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(partsOf(result)[0], contains('timed out after 500ms'));
      expect(partsOf(result)[1], contains('started'));
    });

    test('malformed arguments are answered by the floor, not the program',
        () async {
      final harness = await connectedToFixture();

      final result = await harness.connection.callTool(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': [1, 2],
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(partsOf(result).join('\n'), contains('args'));
    });

    test('two overlapping calls both land, neither waiting on the other',
        () async {
      final harness = await connectedToFixture();
      final room = Directory.systemTemp.createTempSync('mcp-rendezvous-');
      addTearDown(() => room.deleteSync(recursive: true));
      final first = p.join(room.path, 'first');
      final second = p.join(room.path, 'second');

      // Each call only completes once the other has started, so completing at
      // all is the proof that nothing serialized them.
      final results = await Future.wait([
        harness.connection.callTool(
          CallToolRequest(
            name: 'program',
            arguments: {
              'args': ['rendezvous', first, second],
            },
          ),
        ),
        harness.connection.callTool(
          CallToolRequest(
            name: 'program',
            arguments: {
              'args': ['rendezvous', second, first],
            },
          ),
        ),
      ]).timeout(const Duration(seconds: 20));

      expect(partsOf(results[0])[1], contains('met'));
      expect(partsOf(results[1])[1], contains('met'));
    });
  });

  group('the session', () {
    test('stops a running program when the host closes the channel', () async {
      final harness = await connectedToFixture();

      // Driven on the server's side of the channel: closing the channel aborts
      // the client's pending request by design, so the client cannot witness
      // what became of the program. What is under test is that no spawned
      // process outlives the server.
      final call = harness.server.program.call(
        CallToolRequest(
          name: 'program',
          arguments: {
            'args': ['slow', '30'],
          },
        ),
      );
      // Let the program get as far as its first line before the host leaves.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await harness.server.shutdown();

      // The call returns because the program was stopped, not because it ran
      // its thirty seconds out.
      final result = await call.timeout(const Duration(seconds: 10));
      expect(partsOf(result)[0], contains('exit status:'));
      expect(partsOf(result)[0], isNot(contains('exit status: 0')));
      expect(partsOf(result)[1], contains('started'));
    });
  });
}
