import 'dart:io';

import 'package:bentos_userland/mem2.dart';

Future<void> main(List<String> args) async {
  final runner = MemRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
