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

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: llm <prompt>');
    exit(2);
  }
  final prompt = args.join(' ');
  final devicePath = Platform.environment['BENTOS_LLM_DEVICE'] ??
      '/dev/llm/anthropic/claude-haiku-4-5';

  final device = BentosChatDevice(_portal(), devicePath);

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
Bentos _portal() {
  // DRIVER SLOT (D3): when lib/anthropic-chat-driver lands, serve it here:
  //
  //   final driver = anthropicChatDriver();           // P4 ConfiguredStreamDriver
  //   final pair = StreamChannelController<Uint8List>();
  //   driver.serveChannel(pair.foreign);
  //   return InProcessBentos(capMap: {'/dev/llm/anthropic/': pair.local});
  //
  stderr.writeln(
    'llm: no chat driver wired yet — the Anthropic driver lands with D3 '
    '(see TODO.md); this coreutil is ready and waiting for it.',
  );
  exit(3);
}
