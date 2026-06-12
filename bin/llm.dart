library;

import 'dart:io';

import '_drivers.dart';
import 'package:llm/llm.dart';

void main(List<String> args) async {
  registerBundledLlmDrivers();
  exit(await LlmRunner().run(args, stdinHasPrompt: !stdin.hasTerminal));
}
