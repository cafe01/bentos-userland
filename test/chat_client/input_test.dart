import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat_client/input.dart';
import 'package:bentos_userland/src/chat_client/intent.dart';
import 'package:bentos_userland/src/chat_client/room.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');

Session _session({int rooms = 1}) => Session([
      for (var i = 0; i < rooms; i++) Room(channel: FakeChannel(name: 'room$i', me: _me)),
    ]);

void main() {
  group('Input', () {
    const input = Input();

    test('a plain character inserts into the composer', () {
      final session = _session();
      final effect = input.handle(const KeyPress(Key.char, char: 'h'), session);

      expect(session.currentRoom.composer.text, 'h');
      expect(effect.intent, isNull);
      expect(effect.persistable, isFalse);
    });

    test('a paste inserts the whole block in one move, embedded newline included as text', () {
      final session = _session();
      session.currentRoom.composer.insert('before ');

      final effect = input.handle(const KeyPress(Key.paste, char: 'line one\nline two'), session);

      expect(session.currentRoom.composer.text, 'before line one\nline two');
      expect(effect.intent, isNull);
    });

    test('enter on plain prose returns Speak and does not clear the buffer', () {
      final session = _session();
      session.currentRoom.composer.insert('status?');

      final effect = input.handle(const KeyPress(Key.enter), session);

      expect(effect.intent, isA<Speak>());
      expect(effect.persistable, isTrue);
      expect(session.currentRoom.composer.text, 'status?'); // Room.speak() clears it, not Input
    });

    test('enter on an empty buffer does nothing', () {
      final session = _session();
      final effect = input.handle(const KeyPress(Key.enter), session);
      expect(effect.intent, isNull);
      expect(effect.quit, isFalse);
    });

    test('a single leading slash is a command, never spoken', () {
      final session = _session();
      session.currentRoom.composer.insert('/mute here');

      final effect = input.handle(const KeyPress(Key.enter), session);

      expect(effect.intent, isA<InvokeCommand>());
      final invoke = effect.intent as InvokeCommand;
      expect(invoke.verb, 'mute');
      expect(invoke.args, ['here']);
    });

    test('/quit is read as a quit, not an Invoke', () {
      final session = _session();
      session.currentRoom.composer.insert('/quit');

      final effect = input.handle(const KeyPress(Key.enter), session);

      expect(effect.quit, isTrue);
      expect(effect.intent, isNull);
    });

    test('a doubled leading slash escapes into speech with one slash', () {
      final session = _session();
      session.currentRoom.composer.insert('//help');

      final effect = input.handle(const KeyPress(Key.enter), session);

      expect(effect.intent, isA<Speak>());
      expect(session.currentRoom.composer.text, '/help');
    });

    test('tab toggles focus between composer and transcript', () {
      final session = _session();
      expect(session.focus, Focus.composer);

      input.handle(const KeyPress(Key.tab), session);
      expect(session.focus, Focus.transcript);

      input.handle(const KeyPress(Key.tab), session);
      expect(session.focus, Focus.composer);
    });

    test('roomByIndex switches the current room and is persistable', () {
      final session = _session(rooms: 2);
      final effect = input.handle(const KeyPress(Key.roomByIndex, index: 1), session);

      expect(session.currentIndex, 1);
      expect(effect.persistable, isTrue);
    });

    test('up/down browse composer history when focused on it', () {
      final session = _session();
      session.currentRoom.composer.insert('first');
      session.currentRoom.composer.submit();

      input.handle(const KeyPress(Key.up), session);

      expect(session.currentRoom.composer.text, 'first');
    });

    test('up/down scroll the transcript when focused on it', () {
      final session = _session();
      session.focusTranscript();
      session.currentRoom.transcript.append(SystemLine('note', DateTime(2026)));

      input.handle(const KeyPress(Key.up), session);

      expect(session.currentRoom.transcript.scrollFromBottom, 1);
    });
  });
}
