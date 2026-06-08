/// The in-process kernel stand-in's **boot layer** — where the `/dev/llm/*`
/// device is wired to a real chat driver and its credentials.
///
/// This is the config layer the `llm` spec (§1 warning) carves OUT of the
/// coreutil. Key reading, vendor routing and driver construction live here,
/// behind the device — never in an app's `main`. A coreutil calls
/// [bootLlmDevice] and from then on only ever speaks `open`/`write`/`read`
/// against the returned [Bentos]; it never learns which vendor answered.
///
/// In a shipped HumanOS this wiring is the kernel's driver table, populated
/// from system config. In-process it is this function. The seam is the same:
/// the program above is inert.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';
import 'package:stream_channel/stream_channel.dart';

import 'bentos_userland.dart';

/// A `/dev/llm/*` device could not be wired — a config-layer failure (unknown
/// vendor, missing credential, malformed path). Distinct from [BentosException],
/// which is a syscall-surface failure once a session is live.
class LlmBootException implements Exception {
  final String message;
  const LlmBootException(this.message);
  @override
  String toString() => message;
}

/// Boots the in-process portal for a single `/dev/llm/<vendor>/<model>` device.
///
/// Parses the vendor and model out of [devicePath], reads the matching
/// credential from the environment, constructs the driver, and serves it over
/// the kernel-side end of an in-process channel pair. Returns a [Bentos] whose
/// cap map routes that device path to the driver.
///
/// Throws [LlmBootException] for a malformed path, an unknown vendor, or a
/// missing credential — all config errors the coreutil surfaces and exits on.
Bentos bootLlmDevice(
  String devicePath, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;

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
      anthropicChatDriver(model: model, apiKey: _key(env, 'ANTHROPIC_API_KEY'))
          .serveChannel(pair.foreign);
    case 'openai':
      openaiChatDriver(model: model, apiKey: _key(env, 'OPENAI_API_KEY'))
          .serveChannel(pair.foreign);
    default:
      throw LlmBootException('unknown vendor "$vendor"');
  }
  return InProcessBentos(capMap: {'/dev/llm/$vendor/': pair.local});
}

String _key(Map<String, String> env, String name) {
  final v = env[name];
  if (v == null || v.isEmpty) {
    throw LlmBootException('$name is not set');
  }
  return v;
}
