/// The in-process kernel stand-in's **boot layer** — pure path → driver routing,
/// vendor-agnostic.
///
/// This is the config layer the `llm` spec (§1) carves OUT of the coreutil:
/// it decides WHICH driver a `/dev/llm/<vendor>/<model>` path instantiates and
/// serves. Nothing more. It does NOT read, validate, or pass credentials — that
/// is the driver's own job, resolved from the runtime environment at `open`
/// (an absent key fails the device with EACCES, behind the device, not here).
///
/// The lib knows the *contract* — a `<vendor>` string maps to an
/// [LlmDriverFactory] — but never the vendors themselves. Concrete vendor wiring
/// (anthropic, openai) lives OUTSIDE the published lib, in `example/`. A
/// distribution registers the drivers it ships before booting a device; the lib
/// stays free of any concrete-driver dependency. This is what keeps the
/// dependency graph acyclic and the package publishable.
///
/// A coreutil calls [bootLlmDevice] and from then on only ever speaks
/// `open`/`write`/`read` against the returned [Bentos]; it never learns which
/// vendor answered. In a shipped HumanOS this routing is the kernel's driver
/// table; in-process it is this function. The seam is the same: the program
/// above is inert.
library;

import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

import 'bentos_userland.dart';

/// Constructs a vendor driver for [model] and serves it over the kernel-side
/// [channel] end. The lib holds the SHAPE; the vendor is supplied from outside
/// via [registerLlmDriver] (see `example/boot_with_drivers.dart`).
typedef LlmDriverFactory = void Function(
  String model,
  StreamChannel<Uint8List> channel,
);

final Map<String, LlmDriverFactory> _registry = {};

/// Binds [factory] to [vendor] in the boot routing table. Idempotent per vendor —
/// the last registration wins. Vendor wiring is a distribution/dev concern, never
/// part of the published lib.
void registerLlmDriver(String vendor, LlmDriverFactory factory) {
  _registry[vendor] = factory;
}

/// Drops all registered vendors. Test/setup helper — lets a suite control the
/// routing table without process-global bleed between groups.
void clearLlmDrivers() => _registry.clear();

/// A `/dev/llm/*` path could not be ROUTED — a malformed path or a vendor with no
/// registered driver. This is the routing layer's only failure class; credential
/// problems are NOT boot errors — they surface as a [BentosException] (EACCES)
/// from behind the device, once a session is opened.
class LlmBootException implements Exception {
  final String message;
  const LlmBootException(this.message);
  @override
  String toString() => message;
}

/// Boots the in-process portal for a single `/dev/llm/<vendor>/<model>` device.
///
/// Parses the vendor and model out of [devicePath], looks up the vendor's
/// registered [LlmDriverFactory], and serves it over the kernel-side end of an
/// in-process channel pair. Returns a [Bentos] whose cap map routes that device
/// path to the driver.
///
/// Throws [LlmBootException] for a malformed path or an unregistered vendor —
/// routing errors. A missing credential is NOT raised here: it fails the later
/// `open` with EACCES, surfaced to the consumer as a [BentosException].
Bentos bootLlmDevice(String devicePath) {
  final parts = devicePath.split('/').where((p) => p.isNotEmpty).toList();
  // parts == ['dev', 'llm', <vendor>, <model...>]
  if (parts.length < 4 || parts[0] != 'dev' || parts[1] != 'llm') {
    throw LlmBootException(
      'bad device path "$devicePath" (expected /dev/llm/<vendor>/<model>)',
    );
  }
  final vendor = parts[2];
  final model = parts.sublist(3).join('/');

  final factory = _registry[vendor];
  if (factory == null) {
    throw LlmBootException(
      'unknown vendor "$vendor" (no driver registered — '
      'wire it via registerLlmDriver, see example/boot_with_drivers.dart)',
    );
  }

  final pair = StreamChannelController<Uint8List>();
  factory(model, pair.foreign);
  return InProcessBentos(capMap: {'/dev/llm/$vendor/': pair.local});
}
