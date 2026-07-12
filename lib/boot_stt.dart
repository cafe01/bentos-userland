/// The in-process boot layer for the `stt` coreutil — pure path → driver
/// routing, vendor-agnostic. The Path-A seat (FUSE/byte-wire deferred): it
/// returns the driver OBJECT, and the coreutil speaks the object API
/// (`open`/`write`/`inputEnd`/`read`) directly. When the byte-wire lands as the
/// next subsystem, this seat swaps to an `InProcessBentos` and the face above
/// does not change a line — the projection is wire-invariant.
///
/// Mirrors `boot.dart` (the `llm` seat): a `<vendor>` string maps to a driver
/// factory; the lib never names a vendor. Concrete wiring lives OUTSIDE the
/// published lib, in `bin/_stt_drivers.dart`, so the dependency graph stays
/// acyclic and the package publishable.
library;

import 'package:stt_inference/stt_inference.dart';

/// Constructs a [TranscriptionDriver] for [model]. The lib holds the SHAPE;
/// the vendor is supplied from outside via [registerTranscribeDriver].
typedef TranscribeDriverFactory = TranscriptionDriver Function(String model);

/// Constructs a [LiveTranscriptionDriver] for [model]. Vendor-blind like its
/// transcribe sibling; the session state type [P] is the provider's secret, so
/// the routing layer holds it as `Object?`.
typedef LiveDriverFactory = LiveTranscriptionDriver<Object?> Function(
    String model);

final Map<String, TranscribeDriverFactory> _transcribeRegistry = {};
final Map<String, LiveDriverFactory> _liveRegistry = {};

/// Binds [factory] to [vendor] in the transcribe routing table. Idempotent per
/// vendor — the last registration wins.
void registerTranscribeDriver(String vendor, TranscribeDriverFactory factory) {
  _transcribeRegistry[vendor] = factory;
}

/// Binds [factory] to [vendor] in the live routing table (the `live` verb).
/// Idempotent per vendor — the last registration wins.
void registerLiveDriver(String vendor, LiveDriverFactory factory) {
  _liveRegistry[vendor] = factory;
}

/// Drops all registered vendors, both verbs. Test/setup helper — no
/// process-global bleed between groups.
void clearSttDrivers() {
  _transcribeRegistry.clear();
  _liveRegistry.clear();
}

/// A `/dev/stt/*` path could not be ROUTED — a malformed path or a vendor with
/// no registered driver. This is the routing layer's only failure class;
/// credential problems are NOT boot errors — they surface as a [DriverError]
/// (EACCES) from behind the device, once a session is opened.
class SttBootException implements Exception {
  final String message;
  const SttBootException(this.message);
  @override
  String toString() => message;
}

/// Boots the transcribe driver for a single
/// `/dev/stt/<vendor>/<model>/transcribe` device path (§1.1).
///
/// The trailing `transcribe` is the protocol segment (§5.4 seam 3) the coreutil
/// mapped from its verb; it fixes the class (`TranscriptionDriver`). Parses the
/// vendor and model out, looks up the vendor's factory, and returns the driver.
///
/// Throws [SttBootException] for a malformed path, a wrong/absent protocol
/// segment, or an unregistered vendor — routing errors. A missing credential is
/// NOT raised here: it fails the later `open` with EACCES.
TranscriptionDriver bootTranscribeDevice(String devicePath) {
  final parts = devicePath.split('/').where((p) => p.isNotEmpty).toList();
  // parts == ['dev', 'stt', <vendor>, <model...>, 'transcribe']
  if (parts.length < 5 ||
      parts[0] != 'dev' ||
      parts[1] != 'stt' ||
      parts.last != 'transcribe') {
    throw SttBootException(
      'bad device path "$devicePath" '
      '(expected /dev/stt/<vendor>/<model>/transcribe)',
    );
  }
  final vendor = parts[2];
  final model = parts.sublist(3, parts.length - 1).join('/');

  final factory = _transcribeRegistry[vendor];
  if (factory == null) {
    throw SttBootException(
      'unknown vendor "$vendor" (no driver registered — '
      'wire it via registerTranscribeDriver, see bin/_stt_drivers.dart)',
    );
  }
  return factory(model);
}

/// Boots the live driver for a single `/dev/stt/<vendor>/<model>/live` device
/// path — the `live` verb's `LiveTranscription` session machine (§2.3). Mirror
/// of [bootTranscribeDevice]; the trailing `live` fixes the class.
///
/// Throws [SttBootException] for a malformed path, a wrong/absent protocol
/// segment, or an unregistered vendor. A missing credential is NOT raised here:
/// it fails the later `open` with EACCES.
LiveTranscriptionDriver<Object?> bootLiveDevice(String devicePath) {
  final parts = devicePath.split('/').where((p) => p.isNotEmpty).toList();
  // parts == ['dev', 'stt', <vendor>, <model...>, 'live']
  if (parts.length < 5 ||
      parts[0] != 'dev' ||
      parts[1] != 'stt' ||
      parts.last != 'live') {
    throw SttBootException(
      'bad device path "$devicePath" '
      '(expected /dev/stt/<vendor>/<model>/live)',
    );
  }
  final vendor = parts[2];
  final model = parts.sublist(3, parts.length - 1).join('/');

  final factory = _liveRegistry[vendor];
  if (factory == null) {
    throw SttBootException(
      'unknown vendor "$vendor" (no live driver registered — '
      'wire it via registerLiveDriver, see bin/_stt_drivers.dart)',
    );
  }
  return factory(model);
}
