/// `llm session` — the shell's face on a `.llm` entity.
///
/// Today it carries one verb, and that verb is not for a person: `run` is the
/// assistant's body, the command a session's arming names in its subscription
/// table. The hook wakes it, it folds, it works if it is owed, it exits. The
/// verbs a person drives — open, say, return — land when a face pulls them.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../../../entity.dart';
import '../../../../llm_session.dart';

class SessionCommand extends Command<int> {
  SessionCommand() {
    addSubcommand(SessionRunCommand());
  }

  @override
  String get name => 'session';

  @override
  String get description => 'Act on a `.llm` session entity.';
}

class SessionRunCommand extends Command<int> {
  SessionRunCommand({StringSink? err}) : err = err ?? stderr {
    argParser.addOption(
      'ref',
      help: 'The session line to answer.',
      defaultsTo: mainRef,
    );
    argParser.addOption(
      'as',
      help: "The identity the reply is signed with.",
      defaultsTo: 'model',
    );
  }

  final StringSink err;

  @override
  String get name => 'run';

  @override
  String get description =>
      'Wake the assistant on a session: fold, answer if inference is owed, exit.';

  @override
  String get invocation => 'llm session run <session.llm> [--ref <ref>]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      err.writeln('llm session run: no session given');
      return 64; // EX_USAGE
    }
    final dir = Directory(rest.first);
    if (!dir.existsSync()) {
      err.writeln('llm session run: no session at "${dir.path}"');
      return 66; // EX_NOINPUT
    }

    final session = Session(
      GitEntity.open(dir),
      ref: argResults!['ref'] as String,
    );
    // Standing down is the ordinary outcome — a body woken by its own commit
    // folds, finds nothing owed, and exits. It is not a failure.
    await SessionRunner(
      session: session,
      identity: argResults!['as'] as String,
    ).wake();
    return 0;
  }
}
