/// The in-process boot layer for the `tts` coreutil — pure path → driver
/// routing, vendor-agnostic. The Path-A seat (FUSE/byte-wire deferred): it
/// returns the driver OBJECT, and the coreutil speaks the object API
/// (`open`/`write`/`inputEnd`/`read`/`ioctl`) directly. When the byte-wire
/// lands as the next subsystem, this seat swaps to an `InProcessBentos` and the
/// face above does not change a line — the projection is wire-invariant.
///
/// Mirrors `boot_stt.dart`, minus the protocol-segment split: the TTS subsystem
/// carries one device class (§1.2), so a `/dev/tts/<vendor>/<model>` path has no
/// verb tail. Concrete wiring lives OUTSIDE the published lib, in
/// `bin/_tts_drivers.dart`, so the dependency graph stays acyclic.
library;

import 'package:tts_inference/tts_inference.dart';

/// Constructs a [SpeechSynthesisDriver] for [model]. The lib holds the SHAPE;
/// the vendor is supplied from outside via [registerTtsDriver]. The provider
/// session type is the provider's secret, held here as `Object?`.
typedef TtsDriverFactory = SpeechSynthesisDriver<Object?> Function(String model);

final Map<String, TtsDriverFactory> _ttsRegistry = {};

/// Binds [factory] to [vendor] in the routing table. Idempotent per vendor —
/// the last registration wins.
void registerTtsDriver(String vendor, TtsDriverFactory factory) {
  _ttsRegistry[vendor] = factory;
}

/// Drops all registered vendors. Test/setup helper — no process-global bleed
/// between groups.
void clearTtsDrivers() {
  _ttsRegistry.clear();
}

/// A `/dev/tts/*` path could not be ROUTED — a malformed path or a vendor with
/// no registered driver. This is the routing layer's only failure class;
/// credential problems are NOT boot errors — they surface as a [DriverError]
/// (EACCES) from behind the device, once a session is opened.
class TtsBootException implements Exception {
  final String message;
  const TtsBootException(this.message);
  @override
  String toString() => message;
}

/// Boots the driver for a single `/dev/tts/<vendor>/<model>` device path
/// (§1.2). Parses the vendor and model out, looks up the vendor's factory, and
/// returns the driver.
///
/// Throws [TtsBootException] for a malformed path or an unregistered vendor —
/// routing errors. A missing credential is NOT raised here: it fails the later
/// `open` with EACCES.
SpeechSynthesisDriver<Object?> bootTtsDevice(String devicePath) {
  final parts = devicePath.split('/').where((p) => p.isNotEmpty).toList();
  // parts == ['dev', 'tts', <vendor>, <model...>]
  if (parts.length < 4 || parts[0] != 'dev' || parts[1] != 'tts') {
    throw TtsBootException(
      'bad device path "$devicePath" '
      '(expected /dev/tts/<vendor>/<model>)',
    );
  }
  final vendor = parts[2];
  final model = parts.sublist(3).join('/');

  final factory = _ttsRegistry[vendor];
  if (factory == null) {
    final known = _ttsRegistry.keys.toList()..sort();
    throw TtsBootException(
      'no device at "$devicePath": unknown vendor "$vendor" '
      '(${known.isEmpty ? 'no vendors available' : 'available vendors: ${known.join(', ')}'})',
    );
  }
  return factory(model);
}
