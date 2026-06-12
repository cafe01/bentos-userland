/// Vendor wiring — **NOT part of the published lib.**
///
/// This is the distribution/example layer where the concrete anthropic + openai
/// drivers are bound behind `/dev/llm`. The published `lib/` depends on neither
/// driver; it knows only the [LlmDriverFactory] contract. A distribution that
/// ships these vendors calls [registerBundledLlmDrivers] once at startup, before
/// booting any `/dev/llm/*` device.
///
/// Keeping this out of `lib/` is what breaks the userland → drivers dependency:
/// the drivers are dev_dependencies (used by example/ and test/), never a
/// dependency of the published surface.
library;

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:bentos_userland/boot.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';

/// Registers the drivers bundled with this distribution into the boot routing
/// table. Call once before [bootLlmDevice] is reachable from a coreutil.
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
