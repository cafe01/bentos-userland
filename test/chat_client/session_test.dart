import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/room.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');
const _cafe = Handle('cafe01', '');

void main() {
  group('Session', () {
    test('refuses an empty room list', () {
      expect(() => Session([]), throwsArgumentError);
    });

    test('starts on room 0 by default', () {
      final session = Session([
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
      ]);

      expect(session.currentIndex, 0);
      expect(session.currentRoom.name, 'fabrica');
    });

    test('switchTo moves the viewport and enters the room, clearing its noise', () {
      final rooms = [
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
      ];
      final session = Session(rooms);
      session.fold(1, const []); // discharge room 1's initial catch-up
      session.fold(1, [_spoke('a')]);
      expect(rooms[1].activity.isQuiet, isFalse);

      session.switchTo(1);

      expect(session.currentIndex, 1);
      expect(rooms[1].activity.isQuiet, isTrue);
    });

    test('switchTo to an out-of-range index is a no-op', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);
      session.switchTo(5);
      expect(session.currentIndex, 0);
    });

    test('a room left behind keeps its own state untouched', () {
      final rooms = [
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
      ];
      final session = Session(rooms);
      rooms[0].fold([_spoke('a'), _spoke('b'), _spoke('c'), _spoke('d')]);
      rooms[0].composer.insert('half-typed');
      rooms[0].transcript.scrollUp(3);

      session.switchTo(1);
      session.switchTo(0);

      expect(rooms[0].composer.text, 'half-typed');
      expect(rooms[0].transcript.scrollFromBottom, 3);
    });

    test('folding the current room clears its noise immediately', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);

      session.fold(0, [_spoke('a')]);

      expect(session.currentRoom.activity.isQuiet, isTrue);
    });

    test('folding a room that is not current lets its noise stand', () {
      final rooms = [
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
      ];
      final session = Session(rooms);

      session.fold(1, const []); // discharge room 1's initial catch-up
      session.fold(1, [_spoke('a')]);

      expect(rooms[1].activity.isQuiet, isFalse);
    });

    test('focus starts on the composer and is held explicitly', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);
      expect(session.focus, Focus.composer);

      session.focusTranscript();
      expect(session.focus, Focus.transcript);

      session.focusComposer();
      expect(session.focus, Focus.composer);
    });
  });
}

Spoke _spoke(String id) => Spoke(
      Message(id: id, author: _cafe, spoken: DateTime(2026, 1, 1), body: 'hi'),
    );
