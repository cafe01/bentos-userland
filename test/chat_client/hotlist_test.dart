import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/hotlist.dart';
import 'package:bentos_userland/src/chat_client/room.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');
const _cafe = Handle('cafe01', '');

void main() {
  group('Hotlist', () {
    Session buildSession(List<String> names) {
      final session = Session([
        for (final n in names) Room(channel: FakeChannel(name: n, me: _me)),
      ]);
      // discharge every room's initial catch-up before a test raises real noise
      for (var i = 0; i < names.length; i++) {
        session.fold(i, const []);
      }
      return session;
    }

    test('a session with no noise has an empty hotlist', () {
      final session = buildSession(['fabrica', 'design', 'mariela']);
      expect(Hotlist.derive(session).entries, isEmpty);
    });

    test('the current room never appears, even when it is noisy', () {
      final session = buildSession(['fabrica', 'design']);
      session.fold(0, [_spoke('a')]);

      expect(Hotlist.derive(session).entries, isEmpty);
    });

    test('a mention outranks plain speech regardless of room order', () {
      final session = buildSession(['fabrica', 'design', 'mariela']);
      session.fold(1, [_spoke('a')]); // room 1: speech
      session.fold(2, [_spoke('b', body: '@alfred status?')]); // room 2: mention

      final entries = Hotlist.derive(session).entries;

      expect(entries.map((e) => e.roomIndex).toList(), [2, 1]);
      expect(entries[0].level, ActivityLevel.mention);
      expect(entries[1].level, ActivityLevel.speech);
    });

    test('ties within a level break by room order', () {
      final session = buildSession(['fabrica', 'design', 'mariela']);
      session.fold(2, [_spoke('a')]);
      session.fold(1, [_spoke('b')]);

      final entries = Hotlist.derive(session).entries;
      expect(entries.map((e) => e.roomIndex).toList(), [1, 2]);
    });
  });
}

Spoke _spoke(String id, {String body = 'hi'}) => Spoke(
      Message(id: id, author: _cafe, spoken: DateTime(2026, 1, 1), body: body),
    );
