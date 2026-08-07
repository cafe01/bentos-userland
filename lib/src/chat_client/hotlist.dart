/// Where the noise is — derived from [Session], never maintained beside it.
///
/// A room's own [Activity] is the source of truth; this is only ever a
/// read, never a second place that could drift from it.
library;

import 'activity.dart';
import 'session.dart';

final class HotlistEntry {
  const HotlistEntry({required this.roomIndex, required this.level, required this.count});

  final int roomIndex;
  final ActivityLevel level;
  final int count;
}

final class Hotlist {
  const Hotlist(this.entries);

  final List<HotlistEntry> entries;

  /// Every room but the current one that is not quiet, mentions first, ties
  /// broken by room order — the current room is excluded because its noise
  /// clears the instant it is entered, so by construction it is never here.
  factory Hotlist.derive(Session session) {
    final entries = <HotlistEntry>[];
    for (var i = 0; i < session.rooms.length; i++) {
      if (i == session.currentIndex) continue;
      final activity = session.rooms[i].activity;
      if (activity.isQuiet) continue;
      entries.add(HotlistEntry(roomIndex: i, level: activity.level, count: activity.count));
    }
    entries.sort((a, b) {
      final byLevel = b.level.index.compareTo(a.level.index);
      if (byLevel != 0) return byLevel;
      return a.roomIndex.compareTo(b.roomIndex);
    });
    return Hotlist(entries);
  }
}
