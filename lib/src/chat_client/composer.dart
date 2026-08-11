/// What is half-typed — per room, since a shared history would put the last
/// thing said in one room one keystroke from being sent into another.
///
/// Cursor movement is over **grapheme clusters**, never code units: an emoji,
/// a ZWJ family, an accented letter composed of two code points — each is one
/// press of backspace, or the demand that a chat survive emoji is only half
/// met.
library;

import 'package:characters/characters.dart';

final class Composer {
  Composer({List<String>? sentHistory})
    : _sent = List.of(sentHistory ?? const []);

  List<String> _clusters = const [];

  /// The cursor, in grapheme clusters — `0..clusters.length`, never a byte or
  /// UTF-16 code-unit offset.
  int _cursor = 0;

  final List<String> _sent;

  /// Null when not browsing history; the index into [_sent] otherwise.
  int? _historyIndex;
  List<String> _draftBeforeHistory = const [];

  String get text => _clusters.join();

  int get cursor => _cursor;

  int get length => _clusters.length;

  List<String> get sentHistory => List.unmodifiable(_sent);

  bool get isBrowsingHistory => _historyIndex != null;

  void insert(String s) {
    _exitHistory();
    final chars = s.characters.toList();
    _clusters = [
      ..._clusters.take(_cursor),
      ...chars,
      ..._clusters.skip(_cursor),
    ];
    _cursor += chars.length;
  }

  /// Deletes the cluster before the cursor. A no-op at the start of the line.
  void backspace() {
    _exitHistory();
    if (_cursor == 0) return;
    _clusters = [..._clusters.take(_cursor - 1), ..._clusters.skip(_cursor)];
    _cursor -= 1;
  }

  /// Deletes the cluster under the cursor. A no-op at the end of the line.
  void deleteForward() {
    _exitHistory();
    if (_cursor >= _clusters.length) return;
    _clusters = [..._clusters.take(_cursor), ..._clusters.skip(_cursor + 1)];
  }

  void moveLeft() {
    if (_cursor > 0) _cursor--;
  }

  void moveRight() {
    if (_cursor < _clusters.length) _cursor++;
  }

  void moveToStart() => _cursor = 0;

  void moveToEnd() => _cursor = _clusters.length;

  void clear() {
    _exitHistory();
    _clusters = const [];
    _cursor = 0;
  }

  void _exitHistory() => _historyIndex = null;

  /// Steps to an older sent line — readline's up-arrow. The line being typed
  /// when history browsing began is remembered and restored by [historyNext]
  /// once the reader steps back past it, never lost to a stray keystroke.
  void historyPrevious() {
    if (_sent.isEmpty) return;
    if (_historyIndex == null) {
      _draftBeforeHistory = _clusters;
      _historyIndex = _sent.length;
    }
    if (_historyIndex == 0) return;
    _historyIndex = _historyIndex! - 1;
    _clusters = _sent[_historyIndex!].characters.toList();
    _cursor = _clusters.length;
  }

  /// Steps to a newer sent line, or back to the draft once past the newest.
  void historyNext() {
    if (_historyIndex == null) return;
    if (_historyIndex! >= _sent.length - 1) {
      _historyIndex = null;
      _clusters = _draftBeforeHistory;
      _cursor = _clusters.length;
      return;
    }
    _historyIndex = _historyIndex! + 1;
    _clusters = _sent[_historyIndex!].characters.toList();
    _cursor = _clusters.length;
  }

  /// Sends the buffer: pushed onto [sentHistory] and the line cleared.
  /// Returns null for a whitespace-only buffer, which is left untouched —
  /// nothing is sent, and nothing is lost from what was being typed.
  String? submit() {
    final body = text;
    if (body.trim().isEmpty) return null;
    _sent.add(body);
    clear();
    return body;
  }
}
