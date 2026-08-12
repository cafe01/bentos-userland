/// What `monitor` has drained — a different question from what a reader has
/// read.
///
/// **This is not the client's read mark.** `chat_client`'s `PersistedState`
/// answers *what has this person seen*; this answers *what has this process
/// already drained*, for a script that calls `monitor --wait` again and again
/// and must not receive the same batch twice. Keeping the two in separate
/// files is not duplication — collapsing them would make a script's polling
/// move a mark the TUI reads as "you saw this", which nobody asked for.
library;

import 'dart:convert';
import 'dart:io';

/// The whole of what this face remembers between invocations of `monitor`,
/// keyed by the full coordinate (`bentos.chat:fabrica`) **and by the
/// participant who drained it**.
///
/// One key per coordinate was wrong on both axes, and only the second axis was
/// written down. Two shells watching two channels must not share a cursor —
/// that was seen. Two *participants* watching one channel must not share one
/// either, and that is the same mistake one level in: the file belongs to the
/// installation, the mark belongs to a person. Under one key, `say` advancing
/// the speaker's own mark advanced everyone's, so the next participant to
/// `--wait` resumed past speech it had never been handed. A drain mark is a
/// claim about who has seen what, and a claim about a person cannot be stored
/// under the name of a machine.
final class MonitorCursors {
  MonitorCursors({Map<String, Map<String, String>>? cursors})
      : cursors = cursors ?? {};

  /// coordinate → participant (the address whole) → commit.
  final Map<String, Map<String, String>> cursors;

  String? of(String coordinate, String participant) =>
      cursors[coordinate]?[participant];

  /// Reads what the file holds, **dropping entries in the old flat shape**
  /// (`coordinate → commit`, with no participant under it).
  ///
  /// Dropped and never migrated onto whoever runs the upgrade: an installation
  /// mark cannot be attributed to a person, so writing it under the current
  /// caller's address would assert a fact nobody knows — which is precisely the
  /// defect this key shape exists to kill. The cost of dropping is one replay
  /// of the channel on the next `--wait`, which is loud, self-correcting, and
  /// already the contract for a coordinate seen for the first time. The cost of
  /// guessing is speech silently never delivered. **Do not turn this into a
  /// migration.**
  factory MonitorCursors.fromJson(Map<String, dynamic> json) {
    final raw = json['cursors'] as Map<String, dynamic>? ?? const {};
    final cursors = <String, Map<String, String>>{};
    for (final entry in raw.entries) {
      final byParticipant = entry.value;
      if (byParticipant is! Map<String, dynamic>) continue;
      final marks = <String, String>{};
      for (final mark in byParticipant.entries) {
        final commit = mark.value;
        if (commit is String) marks[mark.key] = commit;
      }
      if (marks.isNotEmpty) cursors[entry.key] = marks;
    }
    return MonitorCursors(cursors: cursors);
  }

  Map<String, dynamic> toJson() => {'cursors': cursors};

  /// `$XDG_STATE_HOME/bentos.chat/monitor-state.json`, falling back to
  /// `~/.local/state` — the same convention `chat_client`'s state file uses,
  /// at a different name so the two never collide.
  static File defaultFile({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final xdg = env['XDG_STATE_HOME'];
    final home = env['HOME'] ?? '.';
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.local/state';
    return File('$base/bentos.chat/monitor-state.json');
  }

  static MonitorCursors load({File? file}) {
    final f = file ?? defaultFile();
    if (!f.existsSync()) return MonitorCursors();
    return _parse(f.readAsStringSync());
  }

  /// Moves one participant's mark on one coordinate, and **nothing else in the
  /// file**.
  ///
  /// The read-modify-write is done here, under an exclusive lock, rather than
  /// by the caller — which is what makes concurrency survivable. A caller loads
  /// its resume mark, then waits, possibly for minutes, then writes: rewriting
  /// the whole map from that stale copy resurrects every key another process
  /// moved in the meantime, and a resurrected mark hands the same batch out
  /// twice. Re-reading inside the lock and touching one key closes that window
  /// without the caller having to hold anything.
  static void record({
    required String coordinate,
    required String participant,
    required String cursor,
    File? file,
  }) {
    final f = file ?? defaultFile();
    f.parent.createSync(recursive: true);
    // Append opens for read *and* write, creates when absent, and truncates
    // nothing — so the lock is taken before a single byte of the caller's file
    // is at risk. Verified on this SDK: a handle opened this way accepts
    // setPosition, read and truncate, so one handle serves the whole cycle.
    final handle = f.openSync(mode: FileMode.append);
    try {
      handle.lockSync(FileLock.exclusive);
      final length = handle.lengthSync();
      handle.setPositionSync(0);
      final existing = length == 0
          ? MonitorCursors()
          : _parse(utf8.decode(handle.readSync(length), allowMalformed: true));
      (existing.cursors[coordinate] ??= {})[participant] = cursor;
      final bytes =
          utf8.encode(const JsonEncoder.withIndent('  ').convert(existing));
      handle.setPositionSync(0);
      handle.truncateSync(0);
      handle.writeFromSync(bytes);
      handle.flushSync();
      handle.unlockSync();
    } finally {
      handle.closeSync();
    }
  }

  static MonitorCursors _parse(String content) {
    try {
      return MonitorCursors.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
    } on Object {
      // A corrupt or foreign file is not this program's business to repair —
      // it starts fresh rather than refusing to run.
      return MonitorCursors();
    }
  }
}
