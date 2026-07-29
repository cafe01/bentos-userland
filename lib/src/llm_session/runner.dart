/// The assistant's body: transient, woken by the session's hook, answering
/// *owes-inference* by calling the device and then gone. Not a fourth actor —
/// the occupant's behaviour.
///
/// It holds nothing. Every wake folds the log afresh, which is what lets it
/// survive waking on its own commit: idempotence by reading, never by
/// remembering.
library;

import 'dart:convert';

import 'package:chat_inference/chat_inference.dart';

import '../../boot.dart';
import '../chat/bentos_chat_device.dart';
import '../entity/git_entity.dart';
import 'fold.dart';
import 'live.dart';
import 'schema.dart';
import 'session.dart';

/// How a device path becomes a device. The default boots the in-process portal
/// for `/dev/llm/<vendor>/<model>`; which vendor answers is the boot table's
/// business, and the runner never learns it.
typedef DeviceOpener = ChatDevice Function(String devicePath);

ChatDevice openBentosDevice(String devicePath) =>
    BentosChatDevice(bootLlmDevice(devicePath), devicePath);

final class SessionRunner {
  SessionRunner({
    required this.session,
    this.openDevice = openBentosDevice,
    this.identity = 'model',
  });

  final Session session;
  final DeviceOpener openDevice;

  /// Who signs the `reply`. A seat is attributed by author, not by role.
  final String identity;

  /// Woken. Folds, reads its own debt, works if it is owed — and stands down
  /// otherwise. Returns whether it took a turn.
  Future<bool> wake() async {
    final tip = await session.tip;
    final state = await session.state;
    if (state.debt is! OwesInference) return false;

    final channel = state.channel;
    final device = openDevice(channel.deviceId);
    final live = await LiveTurn.open(session.entity);

    final blocks = <int, ChatContent>{};
    final partials = <int, StringBuffer>{};
    final names = <int, ({String id, String name})>{};
    ChatMetadata? metadata;

    try {
      await for (final event in device.infer(state.messages, channel.config)) {
        live.publish(event);
        switch (event) {
          case TextStart(:final index):
            partials[index] = StringBuffer();
          case TextDelta(:final index, :final text):
            (partials[index] ??= StringBuffer()).write(text);
          case TextStop(:final index):
            blocks[index] = TextContent(partials[index]!.toString());
          case ThinkingStart(:final index):
            partials[index] = StringBuffer();
          case ThinkingDelta(:final index, :final text):
            (partials[index] ??= StringBuffer()).write(text);
          case ThinkingStop(:final index):
            blocks[index] = ThinkingContent(text: partials[index]!.toString());
          case FunctionCallStart(:final index, :final id, :final name):
            names[index] = (id: id, name: name);
            partials[index] = StringBuffer();
          case FunctionArgsDelta(:final index, :final partialJson):
            (partials[index] ??= StringBuffer()).write(partialJson);
          case FunctionCallStop(:final index):
            blocks[index] = FunctionCallContent(
              id: names[index]!.id,
              name: names[index]!.name,
              arguments: _args(partials[index]!.toString()),
            );
          case Block(:final index, :final content):
            blocks[index] = content;
          case SignatureDelta():
            break;
          case Complete(metadata: final m):
            metadata = m;
        }
      }
    } finally {
      await live.close();
    }

    final content = [for (final index in blocks.keys.toList()..sort()) blocks[index]!];
    try {
      await session.reply(
        ChatMessage(role: ChatRole.assistant, content: content),
        meta: metadata!,
        marker: TurnMarker(deviceId: channel.deviceId, config: channel.config),
        author: identity,
        expectedParent: tip,
      );
      return true;
    } on RefRaceLost {
      // The loser re-folds: inference is no longer owed, so the turn it just
      // paid for is discarded. Correctness is held by the log; the cost is one
      // wasted model call.
      return false;
    }
  }
}

Map<String, dynamic> _args(String raw) {
  if (raw.trim().isEmpty) return const {};
  final decoded = jsonDecode(raw);
  return decoded is Map ? decoded.cast<String, dynamic>() : const {};
}
