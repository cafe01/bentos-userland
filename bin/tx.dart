import 'dart:io';

import 'package:args/args.dart';
import 'package:bentos_userland/tx.dart';

const _usage = '''
Usage: tx [--entity <name>] [--scope <name>] <group> [<command>] [args]

Groups:
  scope          Existence-level operations (rare)
    new <name>   Create a scope + main worktree
    ls           List the entity's scopes
    rm <name>    Remove an entire existence

  thread         Branch + worktree topology
    new <name>   New branch + worktree (off HEAD)
    ls           Threads + their live worktree paths
    path [name]  Print a thread's worktree dir (default: CWD thread or main)
    fork <new> [<src>]   Branch <new> from <src> (default: main)
    join <src> [<dst>]   Fold <src> into <dst> (default: main)
    rm <name>    Remove a thread's worktree (history stays)

  commit [-m <msg>]     Stage everything + commit in the current worktree
  log                   Commit trace for the current thread (oneline)
  rewind <n>            Reset the worktree back n commits

Entity:  --entity ?? --agent ?? \$BENTOS_AGENT
Scope:   --scope <name> (required for thread commands when not in a worktree)
State:   <place>/.tx/<entity>/<scope>/''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('entity', abbr: 'e', help: 'Entity whose state to operate on.')
    ..addOption('agent', abbr: 'a', help: 'Alias for --entity (legacy).')
    ..addOption('scope', abbr: 's', help: 'Scope to operate on (overrides CWD inference).')
    ..addOption('message', abbr: 'm', help: 'Commit message for `tx commit`.')
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

  final group = parsed.rest.first;
  final rest = parsed.rest.skip(1).toList();

  try {
    final entity = resolveEntity(
      entityFlag: parsed['entity'] as String?,
      agentFlag: parsed['agent'] as String?,
      environment: Platform.environment,
    );
    final placeRoot = resolvePlaceRoot(Directory.current);
    final entityDir = Directory('${placeRoot.path}/.tx/$entity');
    final scopeArg = parsed['scope'] as String?;

    switch (group) {
      case 'scope':
        final txScope = TxScope(entity, entityDir);
        await _handleScope(txScope, rest);

      case 'thread':
        // Resolve scope: --scope flag ?? CWD inference.
        final inferred = resolveFromCwd(entity, placeRoot, Directory.current);
        final scopeName = scopeArg ?? inferred?.scope;
        final cwdThread = inferred?.thread;
        if (scopeName == null) {
          stderr.writeln(
            'tx thread: not inside a scope worktree. '
            'Pass --scope <name>.',
          );
          exit(1);
        }
        final scopeDir = Directory('${entityDir.path}/$scopeName');
        final txThread = TxThread(entity, scopeDir);
        await _handleThread(txThread, rest, cwdThread: cwdThread);

      case 'commit':
      case 'log':
      case 'rewind':
        final day = TxDay(Directory.current);
        await _handleDay(day, group, rest, parsed['message'] as String?);

      default:
        stderr.writeln('tx: unknown group "$group"');
        stderr.writeln(_usage);
        exit(1);
    }
  } on TxResolveError catch (e) {
    stderr.writeln(e);
    exit(1);
  } on TxGitError catch (e) {
    stderr.writeln(e);
    exit(2);
  }
}

Future<void> _handleScope(TxScope scope, List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('tx scope: requires a command (new / ls / rm).');
    exit(1);
  }
  switch (args[0]) {
    case 'new':
      if (args.length < 2) {
        stderr.writeln('tx scope new: requires a name.');
        exit(1);
      }
      await scope.newScope(args[1]);
    case 'ls':
      for (final name in scope.listScopes()) {
        stdout.writeln(name);
      }
    case 'rm':
      if (args.length < 2) {
        stderr.writeln('tx scope rm: requires a name.');
        exit(1);
      }
      scope.removeScope(args[1]);
    default:
      stderr.writeln('tx scope: unknown command "${args[0]}" (new / ls / rm).');
      exit(1);
  }
}

Future<void> _handleThread(
  TxThread thread,
  List<String> args, {
  String? cwdThread,
}) async {
  if (args.isEmpty) {
    stderr.writeln('tx thread: requires a command (new / ls / path / fork / join / rm).');
    exit(1);
  }
  switch (args[0]) {
    case 'new':
      if (args.length < 2) {
        stderr.writeln('tx thread new: requires a name.');
        exit(1);
      }
      await thread.newThread(args[1]);

    case 'ls':
      await thread.listThreads(cwdPath: Directory.current.absolute.path);

    case 'path':
      await thread.printPath(
        name: args.length >= 2 ? args[1] : null,
        cwdThread: cwdThread,
      );

    case 'fork':
      if (args.length < 2) {
        stderr.writeln('tx thread fork: requires a name for the new thread.');
        exit(1);
      }
      await thread.fork(args[1], src: args.length >= 3 ? args[2] : 'main');

    case 'join':
      if (args.length < 2) {
        stderr.writeln('tx thread join: requires a source thread name.');
        exit(1);
      }
      await thread.join(args[1], dst: args.length >= 3 ? args[2] : 'main');

    case 'rm':
      if (args.length < 2) {
        stderr.writeln('tx thread rm: requires a name.');
        exit(1);
      }
      await thread.removeThread(args[1]);

    default:
      stderr.writeln('tx thread: unknown command "${args[0]}".');
      exit(1);
  }
}

Future<void> _handleDay(
  TxDay day,
  String verb,
  List<String> args,
  String? messageFlag,
) async {
  switch (verb) {
    case 'commit':
      await day.commit(message: messageFlag ?? 'tx commit');

    case 'log':
      await day.log();

    case 'rewind':
      if (args.isEmpty) {
        stderr.writeln('tx rewind: requires a count (number of commits).');
        exit(1);
      }
      final n = int.tryParse(args[0]);
      if (n == null) {
        stderr.writeln('tx rewind: "${args[0]}" is not a number.');
        exit(1);
      }
      await day.rewind(n);
  }
}
