import 'dart:io';

import 'package:bentos_userland/mcp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  group('resolution', () {
    test('a path is resolved as itself', () {
      final resolved = resolveProgram(fixtureProgram);

      expect(resolved, p.absolute(fixtureProgram));
      expect(File(resolved!).existsSync(), isTrue);
    });

    test('a bare name is resolved through PATH', () {
      final resolved = resolveProgram('sh');

      expect(resolved, isNotNull);
      expect(p.isAbsolute(resolved!), isTrue);
      expect(p.basename(resolved), 'sh');
      expect(File(resolved).existsSync(), isTrue);
    });

    test('a name nothing answers to resolves to nothing', () {
      expect(resolveProgram('no-such-program-anywhere-at-all'), isNull);
    });

    test('a file that is not executable is not a program', () {
      final room = Directory.systemTemp.createTempSync('mcp-resolution-');
      addTearDown(() => room.deleteSync(recursive: true));
      final inert = File(p.join(room.path, 'inert'))
        ..writeAsStringSync('not a program\n');

      expect(resolveProgram(inert.path), isNull);
      expect(
        resolveProgram('inert', environment: {'PATH': room.path}),
        isNull,
      );

      Process.runSync('chmod', ['755', inert.path]);

      expect(
        resolveProgram('inert', environment: {'PATH': room.path}),
        inert.path,
      );
    });
  });

  group('the tool name', () {
    test('is the basename when the protocol allows it', () {
      expect(toolNameFor('chat-codec'), 'chat-codec');
      expect(toolNameFor('mem_3'), 'mem_3');
    });

    test('maps forbidden characters to - predictably', () {
      expect(toolNameFor('odd name.sh'), 'odd-name-sh');
      expect(toolNameFor('bentos.chat'), 'bentos-chat');
    });
  });

  group('preparation', () {
    test('captures the help text verbatim', () async {
      final program = await Program.prepare(fixtureProgram);

      expect(program.name, 'program');
      expect(program.path, p.absolute(fixtureProgram));
      expect(program.helpText, startsWith('fixture — a program'));
    });

    test('refuses a program it cannot resolve', () {
      expect(
        Program.prepare('no-such-program-anywhere-at-all'),
        throwsA(isA<StartupFailure>()),
      );
    });

    test('refuses a program that prints no help', () {
      expect(
        Program.prepare(helplessProgram),
        throwsA(isA<StartupFailure>()),
      );
    });

    test('refuses an invocation naming no program', () {
      expect(prepareFromArgs([]), throwsA(isA<StartupFailure>()));
    });

    test('a word after the program presents that subcommand, not the program',
        () async {
      final program = await prepareFromArgs([fixtureProgram, 'sub']);

      // The description is the subcommand's own. A program's help would
      // describe a surface no caller of this tool can reach.
      expect(program.helpText, startsWith('fixture sub —'));
      expect(program.leading, ['sub']);
      // And the tool is named for what is presented, not for what carries it.
      expect(program.name, 'sub');
    });

    test('an explicit name still wins over the subcommand', () async {
      final program =
          await prepareFromArgs([fixtureProgram, 'sub', '--name', 'spawn']);

      expect(program.name, 'spawn');
    });

    test('refuses a subcommand that describes nothing', () {
      expect(
        prepareFromArgs([fixtureProgram, 'mute']),
        throwsA(isA<StartupFailure>()),
      );
    });
  });

  group('the executable', () {
    // The real binary, spawned: a startup failure must kill the process before
    // any handshake, loudly enough to read in the host's log.
    Future<ProcessResult> runMcp(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/mcp.dart', ...args],
    ).timeout(const Duration(seconds: 60));

    test('dies with exit 2 on an unresolvable program', () async {
      final result = await runMcp(['no-such-program-anywhere-at-all']);

      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('cannot resolve program'));
    });

    test('dies with exit 2 on a program that prints no help', () async {
      final result = await runMcp([helplessProgram]);

      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('no description to present'));
    });

    test('dies with exit 2 when no program is named', () async {
      final result = await runMcp([]);

      expect(result.exitCode, 2);
      expect(result.stdout, isEmpty);
      expect(result.stderr, contains('usage: mcp'));
    });
  });
}
