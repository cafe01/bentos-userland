import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/tx.dart';
import 'package:chat_inference/chat_inference.dart';

/// The seam between `chat` and `tx` on the worktree model: a session is a
/// single `session.jsonl` inside the `(entity, scope, thread)` worktree —
/// one JSONL line per message (`chat` owns the framing; `tx`/git only versions
/// the file). One commit per turn, not per message.
final class ChatSession {
  ChatSession._(this._worktree);

  /// The thread worktree this session lives in:
  /// `<place>/.tx/<entity>/<scope>/<thread>/`.
  final Directory _worktree;

  static const _logName = 'session.jsonl';

  File get _log => File('${_worktree.path}/$_logName');

  /// Opens the ambient session for [entity], defaulting scope/thread to
  /// `main`/`main` (the conformance defaults — the rich app schema, scope=user
  /// + thread=conversation-UUID, belongs to the app build, not the coreutil).
  ///
  /// Creates the scope (and its `main` worktree) on first use; on creation,
  /// [systemMessages] are recorded so the system prompt lands in the log — a
  /// native turn carries its system message.
  static Future<ChatSession> open(
    String entity,
    Directory start, {
    String scope = 'main',
    String thread = 'main',
    List<ChatMessage> systemMessages = const [],
  }) async {
    final entityDir = resolveEntityDir(entity, start);
    final scopeDir = Directory('${entityDir.path}/$scope');
    final worktree = Directory('${scopeDir.path}/$thread');
    final session = ChatSession._(worktree);

    if (!Directory('${scopeDir.path}/.git').existsSync()) {
      // `newScope` lands the `main` worktree; a non-default thread is an
      // explicit branch off it.
      await TxScope(entity, entityDir).newScope(scope);
      if (thread != 'main') {
        await TxThread(entity, scopeDir).newThread(thread);
      }
      for (final m in systemMessages) {
        session._appendLine(m);
      }
    }
    return session;
  }

  /// The conversation so far — decoded from the worktree log, system message
  /// included (it was recorded at establishment). Empty for a fresh, system-less
  /// session. This is how continuity survives across invocations: it lives on
  /// disk, not in memory.
  List<ChatMessage> history() {
    if (!_log.existsSync()) return const [];
    return _decode(_log.readAsBytesSync());
  }

  /// Appends one message to the log — the write-ahead per mutation (user input
  /// before inference, each assistant reaction, each tool-result message). No
  /// commit: the turn boundary commits the whole batch.
  Future<void> record(ChatMessage message) async => _appendLine(message);

  /// Seals the turn — one `tx commit` per turn (turns = commits).
  Future<void> commitTurn({String message = 'chat: turn'}) =>
      TxDay(_worktree).commit(message: message);

  // --- framing (chat's, never tx's) ----------------------------------------

  void _appendLine(ChatMessage m) => _log.writeAsStringSync(
        '${encodeMessageJson(m)}\n',
        mode: FileMode.append,
      );

  static List<ChatMessage> _decode(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    return const LineSplitter()
        .convert(utf8.decode(bytes))
        .where((line) => line.isNotEmpty)
        .map(decodeMessageJson)
        .toList();
  }
}
