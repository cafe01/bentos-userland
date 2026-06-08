/// `chatbot` — the first agent built on the Agent SDK.
///
/// Thin entrypoint: all logic lives in [ChatbotRunner] and the command/domain
/// layers under `lib/`.
library;

import 'dart:io';

import 'package:chatbot/chatbot.dart';

void main(List<String> args) async {
  exit(await ChatbotRunner().run(args));
}
