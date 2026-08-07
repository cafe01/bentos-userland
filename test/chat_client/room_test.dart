import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/room.dart';
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');
const _cafe = Handle('cafe01', '');

Message _msg(String id, Handle author, String body) => Message(
      id: id,
      author: author,
      spoken: DateTime(2026, 1, 1),
      body: body,
    );

void main() {
  group('Room', () {
    test('a fresh room with no persisted mark opens caught up after its first fold', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));

      room.fold([Spoke(_msg('a', _cafe, 'hello')), Spoke(_msg('b', _cafe, 'world'))]);

      expect(room.transcript.unreadCount, 0);
      expect(room.activity.isQuiet, isTrue);
    });

    test('a persisted mark is respected — the first fold does not silently catch up', () {
      final room = Room(
        channel: FakeChannel(name: 'fabrica', me: _me),
        persistedReadMark: 'a',
      );

      room.fold([Spoke(_msg('a', _cafe, 'hello')), Spoke(_msg('b', _cafe, 'world'))]);

      expect(room.transcript.unreadCount, 1);
    });

    test('only the first fold catches up — noise after it counts', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));

      room.fold([Spoke(_msg('a', _cafe, 'hello'))]);
      expect(room.activity.isQuiet, isTrue);

      room.fold([Spoke(_msg('b', _cafe, 'world'))]);
      expect(room.activity.level, ActivityLevel.speech);
      expect(room.transcript.unreadCount, 1);
    });

    test('a spoken mention raises activity louder than plain speech', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));
      room.fold([]); // discharge the initial catch-up on an empty room

      room.fold([Spoke(_msg('a', _cafe, '@alfred status?'))]);

      expect(room.activity.level, ActivityLevel.mention);
    });

    test('a topic change appends a line and raises no activity', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));
      room.fold([]);

      room.fold([TopicChanged('the factory floor', _cafe)]);

      expect(room.topic, 'the factory floor');
      expect(room.transcript.lines, hasLength(1));
      expect(room.transcript.lines.single, isA<TopicLine>());
      expect(room.activity.isQuiet, isTrue);
    });

    test('a roster change replaces the roster and appends no line', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));
      room.fold([]);

      final roster = FakeRoster([
        Participant(handle: _cafe, joined: DateTime(2026, 1, 1)),
      ]);
      room.fold([RosterChanged(roster)]);

      expect(room.roster, same(roster));
      expect(room.transcript.lines, isEmpty);
      expect(room.activity.isQuiet, isTrue);
    });

    test('enter clears noise and marks everything read', () {
      final room = Room(channel: FakeChannel(name: 'fabrica', me: _me));
      room.fold([]);
      room.fold([Spoke(_msg('a', _cafe, 'hello'))]);
      expect(room.activity.isQuiet, isFalse);

      room.enter();

      expect(room.activity.isQuiet, isTrue);
      expect(room.transcript.unreadCount, 0);
    });

    group('speak', () {
      test('on success, submits the buffer and clears it', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final room = Room(channel: channel);
        room.composer.insert('raising the install gate');

        final result = await room.speak();

        expect(result, isA<Acted>());
        expect(channel.spoken, ['raising the install gate']);
        expect(room.composer.text, '');
        expect(room.composer.sentHistory, ['raising the install gate']);
      });

      test('on refusal, the composing buffer is untouched', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me)
          ..sayResult = const Refused('not a member');
        final room = Room(channel: channel);
        room.composer.insert('raising the install gate');

        final result = await room.speak();

        expect(result, isA<Refused>());
        expect(channel.spoken, isEmpty);
        expect(room.composer.text, 'raising the install gate');
        expect(room.composer.sentHistory, isEmpty);
      });

      test('on a stumble, the composing buffer is untouched', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me)..sayResult = const Stumbled(3);
        final room = Room(channel: channel);
        room.composer.insert('raising the install gate');

        final result = await room.speak();

        expect(result, isA<Stumbled>());
        expect(room.composer.text, 'raising the install gate');
      });

      test('speaking an empty buffer sends nothing and returns null', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final room = Room(channel: channel);

        final result = await room.speak();

        expect(result, isNull);
        expect(channel.spoken, isEmpty);
      });
    });
  });
}
