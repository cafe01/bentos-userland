import 'dart:io';

import 'package:args/args.dart';
import 'package:tx/tx.dart';

const _usage = '''
Usage: tx [--agent <name>] <command>

Commands (D1):
  new       open a fresh session and make it current (prints the session id)
  append    read bytes from stdin, commit them to the current session
  cat       stream the current session's accumulated bytes to stdout

State lives at <place>/.tx/<entity>/, resolved like .mem.
entity = --agent <name> ?? \$BENTOS_AGENT''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('agent', abbr: 'a', help: 'The entity whose log to operate on.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on ArgParserException catch (e) {
    stderr.writeln('tx: ${e.message}');
    stderr.writeln(_usage);
    exit(1);
  }

  if (parsed['help'] as bool || parsed.rest.isEmpty) {
    stdout.writeln(_usage);
    exit(parsed['help'] as bool ? 0 : 1);
  }

  final command = parsed.rest.first;

  try {
    final entity = resolveEntity(parsed['agent'] as String?, Platform.environment);
    final dir = resolveRepoDir(entity, Directory.current);
    final repo = TxRepo(dir, entity);

    switch (command) {
      case 'new':
        final sid = await repo.newSession();
        stdout.writeln(sid);
      case 'append':
        await repo.append(await _readStdinBytes());
      case 'cat':
        stdout.add(repo.cat());
      default:
        stderr.writeln('tx: unknown command "$command"');
        stderr.writeln(_usage);
        exit(1);
    }
  } on TxResolveError catch (e) {
    stderr.writeln(e);
    exit(1);
  } on TxNoSessionError catch (e) {
    stderr.writeln(e);
    exit(1);
  } on TxGitError catch (e) {
    stderr.writeln(e);
    exit(2);
  }
}

Future<List<int>> _readStdinBytes() async {
  final bytes = <int>[];
  await for (final chunk in stdin) {
    bytes.addAll(chunk);
  }
  return bytes;
}
