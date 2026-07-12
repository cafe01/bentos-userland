// Driver registration for bin/ shells — NOT part of the published lib.
import 'package:bentos_userland/boot_tts.dart';
import 'package:openai_tts_driver/openai_tts_driver.dart';

void registerBundledTtsDrivers() {
  registerTtsDriver('openai', (model) => openaiTtsDriver(model: model));
}
