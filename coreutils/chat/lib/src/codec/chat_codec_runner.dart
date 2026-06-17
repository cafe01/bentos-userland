library;

import 'package:args/command_runner.dart';

CommandRunner<int> buildChatCodecRunner() {
  return CommandRunner<int>(
    'chat-codec',
    'The ChatInference data model as a CLI codec.\n'
    'Construct, transcode, inspect, and fold ChatContent / ChatMessage / ChatEvent from the shell.',
  );
}
