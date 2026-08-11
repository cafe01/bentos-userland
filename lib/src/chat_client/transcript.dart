/// What is in a room, and where the unread line goes.
///
/// Pure: no `dart:io`, no clock of its own, no framework. A [Transcript] holds
/// lines in the order they landed — [Channel.history]'s order, never the
/// order a ULID would sort in — plus the read mark. Where a reader has
/// scrolled to is not a fact about the conversation and lives in the render
/// adapter instead, against nocterm's own scroll controller.
library;

import 'dart:collection';

import '../chat/handle.dart';
import '../chat/model.dart';

/// One displayable row. Not every [TranscriptLine] is a [Message]: a topic
/// change earns a line too, per the noise decision — presence does not.
sealed class TranscriptLine {
  const TranscriptLine();

  DateTime get at;
}

final class SpokenLine extends TranscriptLine {
  const SpokenLine(this.message);

  final Message message;

  @override
  DateTime get at => message.spoken;
}

final class TopicLine extends TranscriptLine {
  const TopicLine(this.topic, this.by, this.at);

  final String topic;
  final Handle by;

  @override
  final DateTime at;
}

enum SystemLineKind { notice, warning }

/// A notice about this program, never the conversation — a refusal or a
/// stumble, so that neither is lost to it happening off-screen. Local to
/// this reader alone: nothing here is spoken into the channel, and nothing
/// here is persisted.
///
/// [kind] defaults to [SystemLineKind.warning], matching every existing
/// caller (`ActRefused`, `ActStumbled`) — a silent default that changed
/// their colour would be a behaviour change hiding in a field nobody asked
/// this page to touch.
final class SystemLine extends TranscriptLine {
  const SystemLine(this.text, this.at, {this.kind = SystemLineKind.warning});

  final String text;
  final SystemLineKind kind;

  @override
  final DateTime at;
}

/// The scrollable buffer of one room.
///
/// **The read mark anchors on a message id, never an index.** A [TopicLine]
/// is cosmetic and carries no id; the mark can only ever name the last
/// [Message] this reader has seen, which is the only anchor that survives a
/// restart — an index does not, since what is at index 12 today is not what
/// was there yesterday.
///
/// **Caught up is the caller's decision, not this class's.** A room opened
/// with no persisted mark should call [markRead] once, before the first
/// [append] — [Transcript] itself does not know whether a null mark means
/// "never read" or "nothing existed yet to read", so it always counts
/// unmarked history as unread. Silence at construction is opt-in.
final class Transcript {
  /// [backing] exists for the suite: a counting [List] double stands in for
  /// it to prove a read touches the tail it needs and never the whole
  /// history. Production never passes it — the default is this transcript's
  /// own growable store.
  Transcript({String? readMark, List<TranscriptLine>? backing})
    : _readMark = readMark,
      _lines = backing ?? <TranscriptLine>[];

  final List<TranscriptLine> _lines;
  String? _readMark;

  /// A live view over the backing store, never a copy: a render reading this
  /// once per keystroke must not pay to duplicate a history it is about to
  /// slice down to a viewport anyway.
  List<TranscriptLine> get lines => UnmodifiableListView(_lines);

  String? get readMark => _readMark;

  /// Appends a line as it lands. Where the viewport sits while this happens
  /// is not this class's concern — that is the render adapter's
  /// `AutoScrollController`, which keeps a reader scrolled away exactly
  /// where they are on its own.
  void append(TranscriptLine line) => _lines.add(line);

  /// Marks everything currently held as read: the mark becomes the id of the
  /// most recent [SpokenLine], or stays null when nothing has been spoken yet.
  void markRead() {
    for (final line in _lines.reversed) {
      if (line is SpokenLine) {
        _readMark = line.message.id;
        return;
      }
    }
  }

  /// How many spoken lines have landed since the mark, and the index in
  /// [lines] of the first of them — one backward pass over the unread tail
  /// answers both, so a caller needing both must read this once rather than
  /// deriving one from the other by walking the transcript a second time.
  /// Everything (and a null boundary held back to the first spoken line), or
  /// nothing, when the mark is null or names a message this transcript never
  /// held (trimmed by a caller that pages history, or simply never seen).
  ({int count, int? boundaryIndex}) unreadTail() {
    var count = 0;
    int? boundaryIndex;
    for (var i = _lines.length - 1; i >= 0; i--) {
      final line = _lines[i];
      if (line is! SpokenLine) continue;
      if (line.message.id == _readMark)
        return (count: count, boundaryIndex: boundaryIndex);
      count++;
      boundaryIndex = i;
    }
    return (count: count, boundaryIndex: boundaryIndex);
  }

  /// How many spoken lines have landed since the mark — see [unreadTail].
  /// A caller that also needs [unreadBoundaryIndex] must call [unreadTail]
  /// itself instead of reading both getters, or it pays for the same
  /// backward pass twice.
  int get unreadCount => unreadTail().count;

  /// The index in [lines] of the first still-unread [SpokenLine] — the row
  /// the "new messages" marker sits in front of. Null when nothing is
  /// unread. See [unreadTail].
  int? get unreadBoundaryIndex => unreadTail().boundaryIndex;
}
