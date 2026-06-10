/// `chatbot resume [session]` — reopen a past session from its disk log.
library;

import 'dart:io';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:bentos_userland/boot.dart';
import 'package:bentos_userland/chat.dart';

import '../../session/session_store.dart';
import 'chatbot_base_command.dart';

class ResumeCommand extends ChatbotBaseCommand {
  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a previous conversation.';

  @override
  String get invocation => 'chatbot resume [<session>]';

  @override
  Future<int> run() async {
    final store = SessionStore.open();
    final arg = argResults!.rest.firstOrNull;

    final String sessionId;
    if (arg != null) {
      final resolved = store.meta(arg)?.id;
      if (resolved == null) {
        stderr.writeln('chatbot: session not found: $arg');
        return 1;
      }
      sessionId = resolved;
    } else {
      final latest = store.latestId();
      if (latest == null) {
        stderr.writeln('chatbot: no sessions found.');
        return 1;
      }
      sessionId = latest;
    }

    final history = store.load(sessionId);
    if (history == null) {
      stderr.writeln('chatbot: failed to load session: $sessionId');
      return 1;
    }

    final meta = store.meta(sessionId)!;
    stderr.writeln('Resuming session ${meta.label} (${history.length} messages).');

    final devicePath = resolveDevicePath();
    final BentosChatDevice device;
    try {
      device = BentosChatDevice(bootLlmDevice(devicePath), devicePath);
    } on LlmBootException catch (e) {
      stderr.writeln('chatbot: $e');
      return 3;
    }

    final conversation = List<ChatMessage>.from(history);

    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();
      if (line == null) {
        stdout.writeln();
        break;
      }
      final input = line.trim();
      if (input == '/exit') break;
      if (input.isEmpty) continue;

      final userMsg = ChatMessage.userText(input);
      conversation.add(userMsg);
      await store.append(sessionId, [userMsg]);

      try {
        final reply = await _streamTurn(device, conversation);
        final assistantMsg = ChatMessage.assistantText(reply);
        conversation.add(assistantMsg);
        await store.append(sessionId, [assistantMsg]);
      } on BentosException catch (e) {
        stderr.writeln('chatbot: $e');
        return 1;
      }
    }

    stderr.writeln('Session ${meta.label} sealed.');
    return 0;
  }

  Future<String> _streamTurn(
    BentosChatDevice device,
    List<ChatMessage> messages,
  ) async {
    final wire = [...systemMessages, ...messages];
    final reply = StringBuffer();
    await for (final event in device.infer(wire, const ChatIOConfig())) {
      switch (event) {
        case TextDelta(:final text):
          stdout.write(text);
          reply.write(text);
        case Block(:final content) when content is TextContent:
          stdout.write(content.text);
          reply.write(content.text);
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
          break;
      }
    }
    return reply.toString();
  }
}
