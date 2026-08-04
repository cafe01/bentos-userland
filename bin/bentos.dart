import 'dart:io';

import 'package:bentos_userland/installer.dart';

Future<void> main(List<String> args) async {
  final runner = BentosRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
