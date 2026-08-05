/// What every verb of the client needs: which conversation, and where it is.
///
/// Both are **global**, on the runner and not on the verbs. A coordinate is
/// ambient — it is the one thing every invocation shares — and a face that makes
/// a person retype it after the verb is a face nobody uses twice.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../session.dart';

/// The two globals, added to the runner's own parser.
void addChatGlobals(ArgParser parser) {
  parser
    ..addOption(
      'session',
      abbr: 's',
      help: 'The conversation, as <entity>:<instance> or <instance>.\n'
          'Defaults to \$CHAT_SESSION.',
    )
    ..addOption(
      'at',
      abbr: 'C',
      help: 'The place the coordinate resolves from.\n'
          'Defaults to the vantage you are standing in.',
    );
}

/// The conversation an invocation is about, read off the globals and the
/// environment. Neither is a stored default: a client that keeps state is a
/// store, and a view owns nothing.
Session sessionFrom(ArgResults? globals, {required String usage}) {
  final spelled = globals?['session'] as String? ??
      Platform.environment['CHAT_SESSION'];
  if (spelled == null || spelled.isEmpty) {
    throw UsageException(
      'chat: no conversation — pass --session or set CHAT_SESSION',
      usage,
    );
  }
  try {
    return Session(Coordinate.parse(spelled, place: placeFrom(globals)));
  } on FormatException catch (e) {
    throw UsageException(e.message, usage);
  }
}

/// The place, which `chat new` needs before any session exists.
String? placeFrom(ArgResults? globals) =>
    globals?['at'] as String? ?? Platform.environment['CHAT_PLACE'];

abstract base class ChatBaseCommand extends Command<int> {
  Session get session => sessionFrom(globalResults, usage: usage);
}
