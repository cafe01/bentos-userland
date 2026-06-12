library;

import 'dart:io';

import '_drivers.dart';
import 'package:chatbot/chatbot.dart';

void main(List<String> args) async {
  registerBundledLlmDrivers();
  exit(await ChatbotRunner().run(args));
}
