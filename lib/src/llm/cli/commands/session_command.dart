/// `llm session` — the shell's face on a `.llm` entity.
///
/// Two kinds of verb live here and they are not the same kind of thing. `run` is
/// the assistant's body: not for a person, but the command a session's arming
/// names in its subscription table. Everything else is a person's hand on the
/// session — `open`, `say`, `return`, `configure`, `rename`, `fork` write
/// transactions, and `show`, `log`, `monitor`, `watch` read.
///
/// No verb here ever calls a device. A face commits and stops; what a commit
/// wakes is the runner's business, and that asymmetry is the loop.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../../../../entity.dart';
import '../../../../llm_session.dart';
import 'session_readout.dart';
import 'session_verbs.dart';

class SessionCommand extends Command<int> {
  SessionCommand() {
    addSubcommand(SessionOpenCommand());
    addSubcommand(SessionSayCommand());
    addSubcommand(SessionReturnCommand());
    addSubcommand(SessionConfigureCommand());
    addSubcommand(SessionRenameCommand());
    addSubcommand(SessionForkCommand());
    addSubcommand(SessionShowCommand());
    addSubcommand(SessionLogCommand());
    addSubcommand(SessionMonitorCommand());
    addSubcommand(SessionWatchCommand());
    addSubcommand(SessionRunCommand());
  }

  @override
  String get name => 'session';

  @override
  String get description => 'Act on a `.llm` session entity.';
}

/// The seat a person's transaction is signed with by default. A seat is
/// attributed by author, so the shell's user is who spoke unless told otherwise.
String get defaultSeat =>
    Platform.environment['USER'] ?? Platform.environment['LOGNAME'] ?? 'person';

/// Where every session verb starts: the entity named on the command line, the
/// line within it, and the seat it signs with.
abstract class SessionCommandBase extends Command<int> {
  SessionCommandBase({
    bool withRef = true,
    bool withSeat = false,
    StringSink? out,
    StringSink? err,
  })  : _withRef = withRef,
        out = out ?? stdout,
        err = err ?? stderr {
    if (withRef) {
      argParser.addOption(
        'ref',
        help: 'The session line to act on.',
        defaultsTo: mainRef,
      );
    }
    if (withSeat) {
      argParser.addOption(
        'as',
        help: 'The seat this transaction is signed with.',
        defaultsTo: defaultSeat,
      );
    }
  }

  final bool _withRef;
  final StringSink out;
  final StringSink err;

  String get ref => _withRef ? argResults!['ref'] as String : mainRef;

  String get seat => argResults!['as'] as String;

  /// A session is a directory, so the face takes a path exactly as any other
  /// coreutil does.
  Directory get entityDir {
    final rest = argResults!.rest;
    if (rest.isEmpty) throw UsageException('a session is required', usage);
    return Directory(rest.first);
  }

  Session get session => Session(GitEntity.open(entityDir), ref: ref);

  /// The text of a turn: the remaining positionals, or piped stdin. A person
  /// types short and pipes long, and both reach the same transaction.
  Future<String> turnText() async {
    final rest = argResults!.rest;
    if (rest.length > 1) return rest.skip(1).join(' ');
    if (!stdin.hasTerminal) {
      final piped = (await stdin.transform(systemEncoding.decoder).join()).trim();
      if (piped.isNotEmpty) return piped;
    }
    throw UsageException('nothing to say — pass text or pipe it', usage);
  }

  Future<int> act();

  @override
  Future<int> run() async {
    try {
      return await act();
    } on EntityGitError catch (e) {
      err.writeln('llm session $name: $e');
      return 66; // EX_NOINPUT
    } on RefRaceLost catch (e) {
      err.writeln('llm session $name: the line moved under this write — $e');
      return 1;
    }
  }
}

class SessionRunCommand extends SessionCommandBase {
  SessionRunCommand({super.err})
      : super(
          withRef: true,
          withSeat: false,
        ) {
    argParser.addOption(
      'as',
      help: "The identity the reply is signed with.",
      defaultsTo: 'model',
    );
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Wake the assistant on a session: fold, answer if inference is owed, exit.';

  @override
  String get invocation => 'llm session run <session.llm> [--ref <ref>]';

  @override
  Future<int> act() async {
    // Standing down is the ordinary outcome — a body woken by its own commit
    // folds, finds nothing owed, and exits. It is not a failure.
    await SessionRunner(session: session, identity: seat).wake();
    return 0;
  }
}
