/// The in-process kernel stand-in's **boot layer** — pure path → driver routing.
///
/// This is the config layer the `llm` spec (§1) carves OUT of the coreutil:
/// it decides WHICH driver a `/dev/llm/<vendor>/<model>` path instantiates and
/// serves. Nothing more. It does NOT read, validate, or pass credentials — that
/// is the driver's own job, resolved from the runtime environment at `open`
/// (an absent key fails the device with EACCES, behind the device, not here).
///
/// A coreutil calls [bootLlmDevice] and from then on only ever speaks
/// `open`/`write`/`read` against the returned [Bentos]; it never learns which
/// vendor answered. In a shipped HumanOS this routing is the kernel's driver
/// table; in-process it is this function. The seam is the same: the program
/// above is inert.
library;

import 'dart:typed_data';

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';
import 'package:stream_channel/stream_channel.dart';

import 'bentos_userland.dart';

/// A `/dev/llm/*` path could not be ROUTED — a malformed path or an unknown
/// vendor. This is the routing layer's only failure class; credential problems
/// are NOT boot errors — they surface as a [BentosException] (EACCES) from
/// behind the device, once a session is opened.
class LlmBootException implements Exception {
  final String message;
  const LlmBootException(this.message);
  @override
  String toString() => message;
}

/// Boots the in-process portal for a single `/dev/llm/<vendor>/<model>` device.
///
/// Parses the vendor and model out of [devicePath], constructs the matching
/// driver (model only — no credential), and serves it over the kernel-side end
/// of an in-process channel pair. Returns a [Bentos] whose cap map routes that
/// device path to the driver.
///
/// Throws [LlmBootException] for a malformed path or an unknown vendor — routing
/// errors. A missing credential is NOT raised here: it fails the later `open`
/// with EACCES, surfaced to the consumer as a [BentosException].
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

  final pair = StreamChannelController<Uint8List>();
  switch (vendor) {
    case 'anthropic':
      anthropicChatDriver(model: model).serveChannel(pair.foreign);
    case 'openai':
      openaiChatDriver(model: model).serveChannel(pair.foreign);
    default:
      throw LlmBootException('unknown vendor "$vendor"');
  }
  return InProcessBentos(capMap: {'/dev/llm/$vendor/': pair.local});
}
