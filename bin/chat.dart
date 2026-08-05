import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_userland/chat_client.dart';

Future<void> main(List<String> args) async {
  final runner = buildChatRunner();
  try {
    exit(await runner.run(withDefaultVerb(args)) ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exit(64);
  } catch (e) {
    stderr.writeln('chat: $e');
    exit(1);
  }
}
