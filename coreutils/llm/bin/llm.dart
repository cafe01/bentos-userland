/// `llm <prompt>` — the inert inference coreutil.
///
/// Opens `/dev/llm/<vendor>/<model>`, writes the prompt as one message, and
/// streams the answer to stdout. That is the whole program. It holds no keys,
/// knows no vendors, constructs no drivers — all of that lives behind the
/// device, in the boot layer (`bentos_userland`'s `boot.dart`). This `main`
/// only ever speaks `open`/`write`/`read` through the [Bentos] surface.
///
/// Device selection: `BENTOS_LLM_DEVICE`, else the default device below.
/// `-v` prints `Complete` metadata to stderr. With no prompt arg and piped
/// stdin, the prompt is read from stdin (`echo … | llm`).
library;

import 'dart:io';

import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/chat.dart';

/// The single piece of app config the spec keeps: a default device so bare
/// `llm "…"` works without typing the FQDN. A path string — no key, no driver.
const _defaultDevice = '/dev/llm/openai/gpt-4o-mini';

void main(List<String> args) async {
  final verbose = args.contains('-v') || args.contains('--verbose');
  final positional = args.where((a) => a != '-v' && a != '--verbose').toList();

  final prompt = await _resolvePrompt(positional);
  if (prompt == null || prompt.trim().isEmpty) {
    stderr.writeln('usage: llm [-v] <prompt>   (or: echo … | llm)');
    exit(2);
  }

  final devicePath =
      Platform.environment['BENTOS_LLM_DEVICE'] ?? _defaultDevice;

  final Bentos bentos;
  try {
    bentos = bootLlmDevice(devicePath);
  } on LlmBootException catch (e) {
    stderr.writeln('llm: $e');
    exit(3);
  }

  final device = BentosChatDevice(bentos, devicePath);
  try {
    await for (final event in device.infer([ChatMessage.userText(prompt)])) {
      switch (event) {
        case TextDelta(:final text):
          stdout.write(text);
        case Complete(:final metadata):
          stdout.writeln();
          if (verbose) {
            stderr.writeln(
              '[${metadata.model} · ${metadata.stopReason} · '
              '${metadata.usage?.inputTokens}in/'
              '${metadata.usage?.outputTokens}out]',
            );
          }
        default:
          break; // thinking / function events: not surfaced by this coreutil.
      }
    }
  } on BentosException catch (e) {
    stderr.writeln('llm: $e');
    exit(1);
  }
}

/// The prompt is the joined args, or — if there are none and stdin is piped —
/// the whole of stdin.
Future<String?> _resolvePrompt(List<String> positional) async {
  if (positional.isNotEmpty) return positional.join(' ');
  if (stdin.hasTerminal) return null;
  return (await stdin.transform(systemEncoding.decoder).join()).trim();
}
