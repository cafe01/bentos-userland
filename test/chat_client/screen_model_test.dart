import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/room.dart';
import 'package:bentos_userland/src/chat_client/screen_model.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');
const _cafe = Handle('cafe01', '');

Spoke _spoke(String id, {String body = 'hi'}) => Spoke(
      Message(id: id, author: _cafe, spoken: DateTime(2026, 1, 1), body: body),
    );

void main() {
  group('ScreenModel', () {
    test('reflects the current room, not the others', () {
      final session = Session([
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
      ]);
      session.currentRoom.composer.insert('raising the install gate');
      session.fold(1, const []); // discharge room 1's initial catch-up
      session.fold(1, [_spoke('a', body: 'in design')]);

      final model = ScreenModel.from(session);

      expect(model.coordinate, 'bentos.chat:fabrica');
      expect(model.composingText, 'raising the install gate');
      expect(model.lines, isEmpty);
    });

    test('carries the composing cursor as a cluster index', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);
      session.currentRoom.composer.insert('hi');
      session.currentRoom.composer.moveLeft();

      final model = ScreenModel.from(session);

      expect(model.composingCursor, 1);
    });

    test('tabs list every room in stable slot order, current one marked', () {
      final session = Session([
        Room(channel: FakeChannel(name: 'fabrica', me: _me)),
        Room(channel: FakeChannel(name: 'design', me: _me)),
        Room(channel: FakeChannel(name: 'mariela', me: _me)),
      ]);
      session.fold(2, const []); // discharge room 2's initial catch-up
      session.fold(2, [_spoke('a')]);

      final model = ScreenModel.from(session);

      expect(model.tabs.map((t) => t.name).toList(), ['fabrica', 'design', 'mariela']);
      expect(model.tabs[0].isCurrent, isTrue);
      expect(model.tabs[2].activityLevel, ActivityLevel.speech);
      expect(model.tabs[2].activityCount, 1);
    });

    test('rosterOverlay mirrors the session flag it was taken from', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);
      session.toggleRosterOverlay();

      final model = ScreenModel.from(session);

      expect(model.rosterOverlay, isTrue);
    });

    test('unreadCount and participants come from the current room', () {
      final session = Session([Room(channel: FakeChannel(name: 'fabrica', me: _me))]);
      session.currentRoom.fold([]); // discharge initial catch-up
      session.currentRoom.fold([_spoke('a')]);
      session.currentRoom.enter(); // being current, this would already be clear via fold,
      // proven independently: enter() is what the model relies on.

      final model = ScreenModel.from(session);

      expect(model.unreadCount, 0);
      expect(model.participants, isEmpty);
    });
  });
}
