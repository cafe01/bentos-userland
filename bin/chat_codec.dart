import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chat/chat.dart';

Future<void> main(List<String> args) async {
  final runner = buildChatCodecRunner();
  try {
    final exitCode = await runner.run(args) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  } catch (e) {
    stderr.writeln('chat-codec: $e');
    exit(1);
  }
}
