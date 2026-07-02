import 'dart:io';

import 'package:bentos_userland/place.dart';

Future<void> main(List<String> args) async {
  final runner = PlaceRunner();
  await runner.run(args);
  exit(runner.exitCode);
}
