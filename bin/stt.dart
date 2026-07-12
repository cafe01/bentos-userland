library;

import 'dart:io';

import 'package:bentos_userland/stt.dart';

import '_stt_drivers.dart';

void main(List<String> args) async {
  registerBundledSttDrivers();
  exit(await SttRunner().run(args, stdinHasAudio: !stdin.hasTerminal));
}
