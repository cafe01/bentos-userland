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
/// keyed by the full coordinate (`bentos.chat:fabrica`) — the same key
/// `ChatCoordinate.whole` prints, since two shells watching two channels must
/// not share a cursor.
final class MonitorCursors {
  MonitorCursors({Map<String, String>? cursors}) : cursors = cursors ?? {};

  final Map<String, String> cursors;

  String? of(String coordinate) => cursors[coordinate];

  factory MonitorCursors.fromJson(Map<String, dynamic> json) =>
      MonitorCursors(
        cursors: (json['cursors'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, v as String)),
      );

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
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return MonitorCursors.fromJson(json);
    } on Object {
      // A corrupt or foreign file is not this program's business to repair —
      // it starts fresh rather than refusing to run.
      return MonitorCursors();
    }
  }

  void save({File? file}) {
    final f = file ?? defaultFile();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}
