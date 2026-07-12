library;

import 'dart:io';

import 'package:bentos_userland/tts.dart';

import '_tts_drivers.dart';

void main(List<String> args) async {
  registerBundledTtsDrivers();
  exit(await TtsRunner().run(args, stdinHasText: !stdin.hasTerminal));
}
