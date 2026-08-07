import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';

/// The command is the entity's own name: one namespace serves identity,
/// repository and PATH entry, so no collision forms as entities are installed.
Future<void> main(List<String> args) async {
  final face = ChatRunner();
  await face.run(args);
  exit(face.exitCode);
}
