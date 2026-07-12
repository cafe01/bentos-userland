// Driver registration for bin/ shells — NOT part of the published lib.
import 'package:bentos_userland/boot_stt.dart';
import 'package:openai_live_stt_driver/openai_live_stt_driver.dart';
import 'package:openai_stt_driver/openai_stt_driver.dart';

void registerBundledSttDrivers() {
  registerTranscribeDriver('openai', (model) => openaiSttDriver(model: model));
  registerLiveDriver('openai', (model) => openaiLiveSttDriver(model: model));
}
