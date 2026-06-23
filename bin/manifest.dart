import 'dart:io';

import 'package:bentos_userland/manifest.dart';

Future<void> main(List<String> args) async {
  final code = await ManifestRunner().run(args);
  exit(code ?? 0);
}
