library;

import 'package:args/command_runner.dart';

import 'commands/content_command.dart';
import 'commands/event_command.dart';
import 'commands/fold_command.dart';
import 'commands/message_command.dart';
import 'commands/validate_command.dart';

CommandRunner<int> buildChatCodecRunner() {
  return CommandRunner<int>(
    'chat-codec',
    'The ChatInference data model as a CLI codec.\n'
    'Construct, transcode, inspect, and fold ChatContent / ChatMessage / ChatEvent from the shell.',
  )
    ..addCommand(MessageCommand())
    ..addCommand(ContentCommand())
    ..addCommand(EventCommand())
    ..addCommand(FoldCommand())
    ..addCommand(ValidateCommand());
}
