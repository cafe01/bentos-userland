/// The fold: the session's state read out of its worktree, and its debt read
/// out of the message list. Nothing stores whose turn it is — every actor woken
/// asks the log, which is what keeps the runner from answering its own reply.
library;

import 'package:chat_inference/chat_inference.dart';

import '../entity/git_entity.dart';
import 'schema.dart';

sealed class Debt {
  const Debt();
}

/// The last word is the user's, or the executor's, and every call is answered.
final class OwesInference extends Debt {
  const OwesInference();

  @override
  String toString() => 'owes-inference';
}

/// The assistant called; these ids have no result yet. The executor's debt,
/// never the assistant's.
final class OwesResults extends Debt {
  const OwesResults(this.callIds);

  final List<String> callIds;

  @override
  String toString() => 'owes-results(${callIds.join(",")})';
}

/// Nothing is owed. A freshly opened session is already here — only the user
/// initiates, and every chain of consequence ends back here.
final class Idle extends Debt {
  const Idle();

  @override
  String toString() => 'idle';
}

final class SessionState {
  const SessionState({
    required this.channel,
    required this.title,
    required this.records,
  });

  final Channel channel;
  final String title;

  /// Ordered by id — lexicographic, which is chronological.
  final List<TurnRecord> records;

  /// The projection at the inference boundary: pure ontology, the envelope left
  /// behind. The device never sees a record.
  List<ChatMessage> get messages => [for (final r in records) r.message];

  TurnRecord? get last => records.isEmpty ? null : records.last;

  /// The system prompt is the leading message, not a knob.
  String? get systemPrompt {
    if (records.isEmpty || records.first.message.role != ChatRole.system) return null;
    return records.first.message.content
        .whereType<TextContent>()
        .map((t) => t.text)
        .join();
  }

  Debt get debt {
    final tail = last;
    if (tail == null) return const Idle();
    switch (tail.message.role) {
      case ChatRole.system:
        return const Idle();
      case ChatRole.assistant:
        final calls = tail.calls;
        return calls.isEmpty ? const Idle() : OwesResults([for (final c in calls) c.id]);
      case ChatRole.user:
        if (!tail.isExecutorTurn) return const OwesInference();
        // The executor's turn accretes: one `return` per call, all landing in
        // one ontology message. The debt is coverage, not message count.
        final answered = {for (final r in tail.results) r.callId};
        final open =
            _pendingCalls(records).where((id) => !answered.contains(id)).toList();
        return open.isEmpty ? const OwesInference() : OwesResults(open);
    }
  }

  /// The call ids of the assistant turn the executor is answering.
  static List<String> _pendingCalls(List<TurnRecord> records) {
    for (final r in records.reversed) {
      if (r.message.role == ChatRole.assistant) {
        return [for (final c in r.calls) c.id];
      }
    }
    return const [];
  }

  static SessionState fold(Tree tree) {
    final ids = tree.keys
        .where((path) => path.startsWith('$messagesDir/'))
        .map((path) => path.substring(messagesDir.length + 1).replaceAll('.json', ''))
        .toList()
      ..sort();
    return SessionState(
      channel: Channel.decode(tree[channelFile]!),
      title: (tree[titleFile] ?? '').trim(),
      records: [for (final id in ids) TurnRecord.decode(id, tree[messagePath(id)]!)],
    );
  }
}
