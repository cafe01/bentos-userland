library;

import 'dart:io';

import '_drivers.dart';
import 'package:bentos_userland/llm.dart';

void main(List<String> args) async {
  registerBundledLlmDrivers();
  exit(await LlmRunner().run(args, stdinHasPrompt: !stdin.hasTerminal));
}
