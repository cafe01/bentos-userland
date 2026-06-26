import 'dart:io';

import 'package:mem/mem.dart';

Future<void> main(List<String> args) async {
  final runner = MemRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
