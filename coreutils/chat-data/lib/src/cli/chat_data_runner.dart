library;

import 'package:args/command_runner.dart';

import 'commands/content_command.dart';
import 'commands/event_command.dart';
import 'commands/fold_command.dart';
import 'commands/msg_command.dart';
import 'commands/validate_command.dart';

CommandRunner<int> buildChatDataRunner() {
  final runner = CommandRunner<int>(
    'chat-data',
    'The ChatInference data model as a CLI codec.\n'
    'Construct, serialize, validate, and fold ChatMessage/ChatEvent from the shell.',
  );

  runner
    ..addCommand(MsgCommand())
    ..addCommand(ContentCommand())
    ..addCommand(EventCommand())
    ..addCommand(ValidateCommand())
    ..addCommand(FoldCommand());

  return runner;
}
