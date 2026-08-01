import 'dart:io';

import 'package:bentos_userland/entity.dart';

Future<void> main(List<String> args) async {
  final runner = EntityRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
