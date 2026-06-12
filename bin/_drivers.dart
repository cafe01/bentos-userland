// Driver registration for bin/ shells — NOT part of the published lib.
import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:bentos_userland/boot.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';

void registerBundledLlmDrivers() {
  registerLlmDriver(
    'anthropic',
    (model, channel) => anthropicChatDriver(model: model).serveChannel(channel),
  );
  registerLlmDriver(
    'openai',
    (model, channel) => openaiChatDriver(model: model).serveChannel(channel),
  );
}
