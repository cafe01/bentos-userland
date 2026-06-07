/// `llm <prompt>` — the first userland consumer of the chat subsystem.
///
/// Opens a chat capability through the Bentos surface, writes the prompt as
/// one message frame, and streams the answer to the terminal as it arrives —
/// each printed delta is one `read()` on the device fd.
///
/// Device selection: `BENTOS_LLM_DEVICE` env var, default
/// `/dev/llm/anthropic/claude-haiku-4-5`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anthropic_chat_driver/anthropic_chat_driver.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';
import 'package:openai_chat_driver/openai_chat_driver.dart';
import 'package:stream_channel/stream_channel.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: llm <prompt>');
    exit(2);
  }
  final prompt = args.join(' ');
  final devicePath = Platform.environment['BENTOS_LLM_DEVICE'] ??
      '/dev/llm/anthropic/claude-haiku-4-5';

  final device = BentosChatDevice(_portal(devicePath), devicePath);

  try {
    await for (final event in device.infer([ChatMessage.userText(prompt)])) {
      switch (event) {
        case TextDelta(:final text):
          stdout.write(text);
        case Complete(:final metadata):
          stdout.writeln();
          stderr.writeln(
            '[${metadata.model} · ${metadata.stopReason} · '
            '${metadata.usage?.inputTokens}in/${metadata.usage?.outputTokens}out]',
          );
        default:
          break; // thinking / function events: not surfaced by this coreutil.
      }
    }
  } on BentosException catch (e) {
    stderr.writeln('llm: $e');
    exit(1);
  }
}

/// The portal this consumer enters the kernel through — in-process for now
/// (architecture §3; the stdlib resolves the door, the program never knows).
///
/// Routes by vendor in the device path (`/dev/llm/<vendor>/<model>`) and serves
/// the matching driver. The consumer above never learns which vendor answered —
/// one device class, N vendors.
Bentos _portal(String devicePath) {
  final parts = devicePath.split('/').where((p) => p.isNotEmpty).toList();
  // parts == ['dev', 'llm', <vendor>, <model>]
  if (parts.length < 4 || parts[0] != 'dev' || parts[1] != 'llm') {
    stderr.writeln('llm: bad device path "$devicePath" '
        '(expected /dev/llm/<vendor>/<model>)');
    exit(3);
  }
  final vendor = parts[2];
  final model = parts.sublist(3).join('/');

  final pair = StreamChannelController<Uint8List>();
  switch (vendor) {
    case 'anthropic':
      anthropicChatDriver(model: model, apiKey: _key('ANTHROPIC_API_KEY'))
          .serveChannel(pair.foreign);
    case 'openai':
      openaiChatDriver(model: model, apiKey: _key('OPENAI_API_KEY'))
          .serveChannel(pair.foreign);
    default:
      stderr.writeln('llm: unknown vendor "$vendor"');
      exit(3);
  }
  return InProcessBentos(capMap: {'/dev/llm/$vendor/': pair.local});
}

String _key(String name) {
  final v = Platform.environment[name];
  if (v == null || v.isEmpty) {
    stderr.writeln('llm: $name is not set');
    exit(3);
  }
  return v;
}
