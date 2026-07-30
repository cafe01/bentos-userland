/// The distribution's driver wiring — which vendors this build of the userland
/// ships, bound into the boot table.
///
/// It is an entrypoint and never part of the core: `boot.dart` holds the
/// *shape* (a vendor string maps to a driver factory) and the published library
/// imports no vendor at all, which is what keeps its dependency graph acyclic.
/// The concrete vendors live here, one import away, for whoever assembles a
/// distribution — the `llm` coreutil at the shell, a window that reads the
/// device catalog, a test that wants the real routing table.
///
/// Call it once, before anything boots a device.
library;

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';

import 'boot.dart';
import 'llm.dart';

void registerBundledLlmDrivers() {
  // The loopback: `/dev/llm/fixture/<scenario>` costs nothing and asks for no
  // credential, so the whole loop can be walked by anyone, anywhere.
  registerLlmDriver(
    fixtureVendor,
    (model, channel) => fixtureChatDriver(model: model).serveChannel(channel),
  );
  registerLlmDriver(
    'anthropic',
    (model, channel) => anthropicChatDriver(model: model).serveChannel(channel),
  );
  registerLlmDriver(
    'openai',
    (model, channel) => openaiChatDriver(model: model).serveChannel(channel),
  );
}
