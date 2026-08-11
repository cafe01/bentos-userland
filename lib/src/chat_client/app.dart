/// The loop, and nothing else: composes [Session] over live [Channel]s,
/// folds what a [Ticker] tick or a keypress produced, and hands down a fresh
/// [ScreenModel]. No `dart:io` terminal, no framework — it is driven by the
/// render adapter, never the other way around.
library;

import 'dart:io';

import '../chat/channel.dart';
import '../chat/outcome.dart';
import 'input.dart';
import 'intent.dart';
import 'persisted_state.dart';
import 'room.dart';
import 'screen_model.dart';
import 'session.dart';
import 'ticker.dart';
import 'transcript.dart';

/// What an act came to, rendered as a line in the room it was tried in —
/// **never swallowed**, per the demand that a stumble or a refusal must be
/// visible as what it is.
sealed class ActNotice {
  const ActNotice();

  String get text;
}

final class ActRefused extends ActNotice {
  const ActRefused(this.reason);

  final String reason;

  @override
  String get text => 'refused: $reason';
}

final class ActStumbled extends ActNotice {
  const ActStumbled(this.attempts);

  final int attempts;

  @override
  String get text => 'stumbled after $attempts attempts — try again';
}

final class ChatProgram {
  ChatProgram({
    required List<Channel> channels,
    required this.ticker,
    this.input = const Input(),
    File? stateFile,
  }) : _stateFile = stateFile {
    if (channels.isEmpty) {
      throw ArgumentError('a program needs at least one room');
    }
    _persisted = PersistedState.load(file: stateFile);
    final rooms = [
      for (final channel in channels)
        Room(
          channel: channel,
          persistedReadMark: _persisted.of(channel.coordinate).readMark,
          sentHistory: _persisted.of(channel.coordinate).sentHistory,
        ),
    ];
    session = Session(
      rooms,
      current: _startIndex(rooms, _persisted.currentCoordinate),
    );
  }

  final Ticker ticker;
  final Input input;
  final File? _stateFile;
  late final PersistedState _persisted;
  late final Session session;

  static int _startIndex(List<Room> rooms, String? coordinate) {
    if (coordinate == null) return 0;
    final index = rooms.indexWhere((r) => r.coordinate == coordinate);
    return index < 0 ? 0 : index;
  }

  ScreenModel get model =>
      ScreenModel.from(session, dispatchConnected: ticker.connected);

  /// The first read: every room folds its opening state, current or not, so
  /// roster and topic are populated before anything is drawn.
  Future<void> start() async {
    await syncAll();
    persist();
  }

  Future<void> syncAll() async {
    for (var i = 0; i < session.rooms.length; i++) {
      final events = await session.rooms[i].channel.sync();
      if (events.isNotEmpty) session.fold(i, events);
    }
  }

  /// One tick: look again, and persist whatever moved.
  Future<void> tick() async {
    await syncAll();
    persist();
  }

  /// One keypress, translated and acted on. Returns the [InputEffect] it
  /// resolved to — `quit` for the caller to act on, and `scroll` for the
  /// render adapter to carry out against a viewport this class never touches.
  Future<InputEffect> handleKeyPress(KeyPress press) async {
    final effect = input.handle(press, session);
    if (effect.quit) {
      persist();
      return effect;
    }
    final intent = effect.intent;
    if (intent != null) {
      await _dispatch(intent);
      ticker.nudge();
    }
    if (effect.persistable || intent != null) persist();
    return effect;
  }

  Future<void> _dispatch(Intent intent) async {
    switch (intent) {
      case Speak():
        final room = session.currentRoom;
        final result = await room.speak();
        final notice = switch (result) {
          null || Acted() => null,
          Refused(reason: final reason) => ActRefused(reason),
          Stumbled(attempts: final attempts) => ActStumbled(attempts),
        };
        if (notice != null) {
          room.transcript.append(SystemLine(notice.text, DateTime.now()));
        }
      case InvokeCommand():
        // No verb is wired for v1 — `quit` is handled by Input itself before
        // an Intent is ever produced.
        break;
    }
  }

  void persist() {
    for (final room in session.rooms) {
      _persisted.rooms[room.coordinate] = RoomState(
        readMark: room.transcript.readMark,
        sentHistory: room.composer.sentHistory,
      );
    }
    _persisted.currentCoordinate = session.currentRoom.coordinate;
    _persisted.save(file: _stateFile);
  }

  void dispose() => ticker.dispose();
}
