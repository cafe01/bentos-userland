/// What is true, never how to draw it.
///
/// The seam between the program and any framework: a value with no
/// dimensions, no colour, no glyphs, no drawing-cursor geometry — those all
/// live below `render`. `ScreenModel` is what a render adapter reads and
/// nothing it decides.
library;

import '../chat/handle.dart';
import '../chat/model.dart';
import 'activity.dart';
import 'hotlist.dart';
import 'session.dart';
import 'transcript.dart';

/// One slot in the room bar — `[1:fabrica(3!)]` — in stable slot order,
/// never reordered by noise. [Hotlist] answers *where is the noise*;
/// this answers *what is in that slot*.
final class RoomTab {
  const RoomTab({
    required this.index,
    required this.name,
    required this.isCurrent,
    required this.activityLevel,
    required this.activityCount,
  });

  final int index;
  final String name;
  final bool isCurrent;
  final ActivityLevel activityLevel;
  final int activityCount;
}

final class ScreenModel {
  const ScreenModel({
    required this.coordinate,
    required this.topic,
    required this.lines,
    required this.scrollFromBottom,
    required this.unreadCount,
    required this.unreadBoundaryIndex,
    required this.participants,
    required this.composingText,
    required this.composingCursor,
    required this.me,
    required this.awayReason,
    required this.now,
    required this.focus,
    required this.tabs,
    required this.hotlist,
  });

  final String coordinate;
  final String? topic;
  final List<TranscriptLine> lines;
  final int scrollFromBottom;
  final int unreadCount;

  /// The index in [lines] of the first unread line — [Transcript]'s own
  /// answer, carried through rather than re-derived from [unreadCount] by
  /// scanning [lines] a second time.
  final int? unreadBoundaryIndex;
  final List<Participant> participants;
  final String composingText;

  /// A grapheme-cluster index into [composingText], never a code-unit or
  /// byte offset — the same unit [Composer] holds it in.
  final int composingCursor;

  final Handle me;

  /// Null when I am here; the reason — possibly empty — when I am away.
  /// [Participant.away]'s own shape: a bool beside it would be a second way
  /// to spell the fact the floor already carries one way.
  final String? awayReason;

  /// The clock at the instant this snapshot was taken — the bar's own
  /// reading, never a fact [Session] holds.
  final DateTime now;

  final Focus focus;
  final List<RoomTab> tabs;
  final Hotlist hotlist;

  /// A snapshot of [session] as it stands right now.
  factory ScreenModel.from(Session session, {DateTime? now}) {
    final room = session.currentRoom;
    final unread = room.transcript.unreadTail();
    return ScreenModel(
      coordinate: room.coordinate,
      topic: room.topic,
      lines: room.transcript.lines,
      scrollFromBottom: room.transcript.scrollFromBottom,
      unreadCount: unread.count,
      unreadBoundaryIndex: unread.boundaryIndex,
      participants: room.roster?.participants.toList() ?? const [],
      composingText: room.composer.text,
      composingCursor: room.composer.cursor,
      me: room.me,
      awayReason: room.roster?.byHandle(room.me.local)?.away,
      now: now ?? DateTime.now(),
      focus: session.focus,
      tabs: [
        for (var i = 0; i < session.rooms.length; i++)
          RoomTab(
            index: i,
            name: session.rooms[i].name,
            isCurrent: i == session.currentIndex,
            activityLevel: session.rooms[i].activity.level,
            activityCount: session.rooms[i].activity.count,
          ),
      ],
      hotlist: Hotlist.derive(session),
    );
  }
}
