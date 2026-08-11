/// What survives a restart — the read mark and sent history, per room, plus
/// which room the viewport last showed. Scroll, activity and the half-typed
/// line are not here on purpose: the medium has no opinion about what
/// anyone has read, so none of this is written into a channel, and it lives
/// keyed by coordinate rather than inside [Room] itself so that reading it
/// is never mistaken for a fact the conversation carries.
library;

import 'dart:convert';
import 'dart:io';

final class RoomState {
  const RoomState({this.readMark, this.sentHistory = const []});

  final String? readMark;
  final List<String> sentHistory;

  factory RoomState.fromJson(Map<String, dynamic> json) => RoomState(
    readMark: json['readMark'] as String?,
    sentHistory: (json['sentHistory'] as List<dynamic>? ?? const [])
        .cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    if (readMark != null) 'readMark': readMark,
    'sentHistory': sentHistory,
  };
}

/// The whole of what this program remembers between runs, keyed by the full
/// coordinate (`bentos.chat:fabrica`).
final class PersistedState {
  PersistedState({Map<String, RoomState>? rooms, this.currentCoordinate})
    : rooms = rooms ?? {};

  final Map<String, RoomState> rooms;
  String? currentCoordinate;

  RoomState of(String coordinate) => rooms[coordinate] ?? const RoomState();

  factory PersistedState.fromJson(Map<String, dynamic> json) {
    final roomsJson = json['rooms'] as Map<String, dynamic>? ?? const {};
    return PersistedState(
      rooms: roomsJson.map(
        (k, v) => MapEntry(k, RoomState.fromJson(v as Map<String, dynamic>)),
      ),
      currentCoordinate: json['currentCoordinate'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'rooms': rooms.map((k, v) => MapEntry(k, v.toJson())),
    if (currentCoordinate != null) 'currentCoordinate': currentCoordinate,
  };

  /// `$XDG_STATE_HOME/bentos.chat/state.json`, falling back to
  /// `~/.local/state` — the state counterpart of `llm`'s own config file at
  /// `$XDG_CONFIG_HOME`.
  static File defaultFile({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final xdg = env['XDG_STATE_HOME'];
    final home = env['HOME'] ?? '.';
    final base = (xdg != null && xdg.isNotEmpty) ? xdg : '$home/.local/state';
    return File('$base/bentos.chat/state.json');
  }

  static PersistedState load({File? file}) {
    final f = file ?? defaultFile();
    if (!f.existsSync()) return PersistedState();
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return PersistedState.fromJson(json);
    } on Object {
      // A corrupt or foreign file is not this program's business to repair —
      // it starts fresh rather than refusing to run.
      return PersistedState();
    }
  }

  void save({File? file}) {
    final f = file ?? defaultFile();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}
