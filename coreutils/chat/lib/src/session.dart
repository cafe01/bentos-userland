import 'dart:convert';

import 'package:chat_inference/chat_inference.dart';
import 'package:tx/tx.dart';

/// The seam between `chat` and `tx`: `chat` owns the framing, `tx` moves
/// opaque bytes. A session record is a `List<ChatMessage>`, one per line
/// (JSONL); `tx` never knows that. This class is the only thing that encodes
/// a message to bytes and decodes bytes back — the content-blind boundary made
/// concrete.
final class ChatSession {
  ChatSession(this._repo);

  final TxRepo _repo;

  /// Opens a session on demand: the first turn for an entity creates one.
  Future<void> ensureOpen() async {
    if (!_repo.hasSession) await _repo.newSession();
  }

  /// The conversation so far — `tx cat` decoded through the framing. Empty for
  /// a fresh session. This is how continuity survives across invocations: it
  /// lives on disk, not in memory.
  List<ChatMessage> history() => _decode(_repo.cat());

  /// Commits one message to the log — one mutation, one `tx append`, one
  /// commit. Called for the user input (before inference — write-ahead), each
  /// assistant reaction, and each tool-result message.
  Future<void> record(ChatMessage message) =>
      _repo.append(_frame(message));

  // --- framing (chat's, never tx's) ----------------------------------------

  static List<int> _frame(ChatMessage m) =>
      utf8.encode('${encodeMessageJson(m)}\n');

  static List<ChatMessage> _decode(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    return const LineSplitter()
        .convert(utf8.decode(bytes))
        .where((line) => line.isNotEmpty)
        .map(decodeMessageJson)
        .toList();
  }
}
