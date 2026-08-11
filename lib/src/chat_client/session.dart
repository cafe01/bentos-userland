/// Where am I, and what else is open.
library;

import '../chat/outcome.dart';
import 'room.dart';

/// Which of the two things on screen a keystroke goes to.
///
/// The framework's focus is a bare bool with no `FocusNode` — routing between
/// the composer and a scrolled transcript is ours to hold, and this is where
/// it is held.
enum Focus { composer, transcript }

final class Session {
  Session(List<Room> rooms, {int current = 0})
    : rooms = List.of(rooms),
      _current = current {
    if (this.rooms.isEmpty) {
      throw ArgumentError('a session needs at least one room');
    }
    if (current < 0 || current >= this.rooms.length) {
      throw RangeError.index(current, this.rooms, 'current');
    }
  }

  final List<Room> rooms;
  int _current;
  Focus _focus = Focus.composer;

  int get currentIndex => _current;

  Room get currentRoom => rooms[_current];

  Focus get focus => _focus;

  void focusComposer() => _focus = Focus.composer;

  void focusTranscript() => _focus = Focus.transcript;

  /// Moves the viewport to another room. The room left behind is untouched —
  /// its scroll position, its noise, its half-typed line all stay exactly as
  /// they were, which is the whole point of a room being a first-class
  /// object and a window only a viewport onto one.
  void switchTo(int index) {
    if (index < 0 || index >= rooms.length) return;
    _current = index;
    currentRoom.enter();
  }

  /// Folds events landed on the room at [index]. The current room's noise
  /// clears the instant it lands, since a room being watched is a room being
  /// read; a room folded while it is not current accrues normally.
  void fold(int index, Iterable<ChannelEvent> events) {
    final room = rooms[index];
    room.fold(events);
    if (index == _current) room.enter();
  }

  /// Adds [room] and switches to it — the room-opening half of R3.1/R3.2/R4.3.
  /// Unlike [switchTo], the room did not exist in [rooms] a moment ago; there
  /// is no separate "insert" step because a room that is not yet open cannot
  /// be switched to.
  void openRoom(Room room) {
    rooms.add(room);
    _current = rooms.length - 1;
    currentRoom.enter();
  }

  /// Whether the roster is shown full-width in place of the transcript —
  /// proprioception, not domain: a fact about the viewport, never persisted,
  /// never read by anything under [Room]. One bit for the whole session, not
  /// per room: it should not silently un-toggle on a room switch.
  bool rosterOverlay = false;

  void toggleRosterOverlay() => rosterOverlay = !rosterOverlay;
}
