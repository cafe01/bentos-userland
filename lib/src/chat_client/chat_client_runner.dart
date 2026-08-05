/// `chat` — the face a person opens over a conversation.
///
/// It speaks the vocabulary of the person, not of the seat: `bentos.llm
/// [actor] [verb]` is porcelain for whoever already knows what a seat is, and
/// both coexist. Everything below this is machinery — the client resolves no
/// function, reads no manifest, lays no environment, and arms nothing it does
/// not itself look through.
library;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'commands/chat_base_command.dart';
import 'commands/monitor_command.dart';
import 'commands/new_command.dart';
import 'commands/repl_command.dart';
import 'commands/say_command.dart';

/// The verb a bare `chat` means. Sitting in the conversation is the thing the
/// face is for; every other verb is a shortcut out of it.
const String defaultVerb = 'repl';

CommandRunner<int> buildChatRunner() {
  final runner = CommandRunner<int>(
    'chat',
    'Talk to a conversation, and look at it.',
  )
    ..addCommand(NewCommand())
    ..addCommand(ReplCommand())
    ..addCommand(SayCommand())
    ..addCommand(MonitorCommand());
  addChatGlobals(runner.argParser);
  return runner;
}

/// The argument list to actually run: a call that names no verb means the
/// default one, with the globals left where the caller typed them.
///
/// The globals are read off a parser of their own rather than by scanning for a
/// word, or `chat -s work` would find a verb in the name of a conversation.
List<String> withDefaultVerb(List<String> args) {
  final globals = ArgParser(allowTrailingOptions: false);
  addChatGlobals(globals);
  try {
    return globals.parse(args).rest.isEmpty ? [...args, defaultVerb] : args;
  } on FormatException {
    // Not ours to answer: hand it to the runner, which owns usage errors.
    return args;
  }
}
