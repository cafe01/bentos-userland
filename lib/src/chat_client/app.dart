/// The loop, and nothing else: composes [Session] over live [Channel]s,
/// folds what a [Ticker] tick or a keypress produced, and hands down a fresh
/// [ScreenModel]. No `dart:io` terminal, no framework — it is driven by the
/// render adapter, never the other way around.
library;

import 'dart:io';

import '../chat/channel.dart';
import '../chat/cli/floor.dart';
import '../chat/outcome.dart';
import 'input.dart';
import 'intent.dart';
import 'persisted_state.dart';
import 'room.dart';
import 'room_command.dart';
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
    required this.floor,
    required this.place,
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
  final ChatFloor floor;
  final String place;
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
        final command = resolveCommand(intent);
        await _execute(command);
    }
  }

  /// One [RoomCommand] carried out. Every arm that calls an act follows the
  /// landing-renders-once law: `join`/`leave`/`away`/`back` append an
  /// immediate notice on [Acted] — no [ChannelEvent] exists for any of the
  /// four — while `setTopic` renders nothing on [Acted] and relies on the
  /// next [syncAll]'s `TopicChanged`. `Refused`/`Stumbled` always render
  /// immediately, for every act alike, through the same [ActNotice]
  /// machinery [Speak] already uses.
  Future<void> _execute(RoomCommand command) async {
    switch (command) {
      case JoinRoom(coordinate: final coordinate, displayName: final displayName):
        final room = await _roomFor(coordinate);
        final result = await room.channel.join(displayName: displayName);
        _renderNotice(room, result, 'joined ${room.coordinate}');

      case LeaveRoom():
        final room = session.currentRoom;
        final result = await room.channel.leave();
        _renderNotice(room, result, 'left ${room.coordinate}');

      case SetAway(reason: final reason):
        final room = session.currentRoom;
        final result = await room.channel.away(reason);
        _renderNotice(room, result, reason == null ? 'away' : 'away: $reason');

      case SetBack():
        final room = session.currentRoom;
        final result = await room.channel.back();
        _renderNotice(room, result, 'back');

      case ShowTopic():
        final room = session.currentRoom;
        final topic = await room.channel.topic();
        room.transcript.append(
          SystemLine(
            topic ?? 'no topic set',
            DateTime.now(),
            kind: SystemLineKind.notice,
          ),
        );

      case SetTopic(text: final text):
        final room = session.currentRoom;
        final result = await room.channel.setTopic(text);
        _renderFailureOnly(room, result);

      case ListChannels():
        final room = session.currentRoom;
        final open = session.rooms.map((r) => r.name).toSet();
        for (final name in floor.channels(place)) {
          final marker = open.contains(name) ? ' (open)' : '';
          room.transcript.append(
            SystemLine(
              '* $name$marker',
              DateTime.now(),
              kind: SystemLineKind.notice,
            ),
          );
        }

      case ShowHelp():
        final room = session.currentRoom;
        for (final line in _helpLines) {
          room.transcript.append(
            SystemLine(line, DateTime.now(), kind: SystemLineKind.notice),
          );
        }

      case UnknownCommand(verb: final verb):
        final room = session.currentRoom;
        room.transcript.append(
          SystemLine('unknown command: /$verb', DateTime.now()),
        );
    }
  }

  static const List<String> _helpLines = [
    '/join [coordinate] — join the current room, or open and join another',
    '/leave — leave the current room',
    '/away [reason] — declare yourself away',
    '/back — declare yourself back',
    '/topic [text] — read, or change, the current room\'s topic',
    '/list — list the channels at this place',
    '/help — this listing',
    '/quit — leave the program',
    'Ctrl+R — show who is here · Alt+1…9 — go to a room · Tab — transcript or composer · Ctrl+C — quit',
  ];

  /// The room to act on for `/join`: the current one when [coordinate] is
  /// null, an already-open room switched to when it names one, or a freshly
  /// minted one — R3.2 read literally: there is no second branch for "this
  /// one doesn't exist yet."
  Future<Room> _roomFor(String? coordinate) async {
    if (coordinate == null) return session.currentRoom;
    final index = session.rooms.indexWhere(
      (room) => room.coordinate == '$chatOntology:$coordinate',
    );
    if (index >= 0) {
      session.switchTo(index);
      return session.rooms[index];
    }
    return _mintRoom(coordinate);
  }

  /// Mints a [Channel] for [coordinate] via [floor], opens it as a [Room]
  /// with no persisted state — a genuinely new room has none — and folds one
  /// [Channel.sync] so it is not blank the instant it is switched to, the
  /// same initial catch-up every room opened at [start] already performs,
  /// run once more, on demand, for one room.
  Future<Room> _mintRoom(String coordinate) async {
    final channel = floor.channel(coordinate, place: place);
    final room = Room(channel: channel);
    session.openRoom(room);
    final events = await channel.sync();
    if (events.isNotEmpty) room.fold(events);
    return room;
  }

  void _renderNotice(Room room, ActResult result, String noticeText) {
    switch (result) {
      case Acted():
        room.transcript.append(
          SystemLine(noticeText, DateTime.now(), kind: SystemLineKind.notice),
        );
      case Refused(reason: final reason):
        room.transcript.append(
          SystemLine(ActRefused(reason).text, DateTime.now()),
        );
      case Stumbled(attempts: final attempts):
        room.transcript.append(
          SystemLine(ActStumbled(attempts).text, DateTime.now()),
        );
    }
  }

  void _renderFailureOnly(Room room, ActResult result) {
    switch (result) {
      case Acted():
        break;
      case Refused(reason: final reason):
        room.transcript.append(
          SystemLine(ActRefused(reason).text, DateTime.now()),
        );
      case Stumbled(attempts: final attempts):
        room.transcript.append(
          SystemLine(ActStumbled(attempts).text, DateTime.now()),
        );
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
