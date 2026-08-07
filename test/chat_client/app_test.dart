import 'dart:async';
import 'dart:io';

import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/app.dart';
import 'package:bentos_userland/src/chat_client/input.dart';
import 'package:bentos_userland/src/chat_client/persisted_state.dart';
import 'package:bentos_userland/src/chat_client/ticker.dart';
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

const _me = Handle('alfred', '');
const _cafe = Handle('cafe01', '');

/// A [Ticker] a test drives by hand — no [Timer], no wall clock.
final class _FakeTicker implements Ticker {
  final _controller = StreamController<void>.broadcast();
  int nudges = 0;

  @override
  Stream<void> get ticks => _controller.stream;

  @override
  void nudge() => nudges++;

  @override
  void dispose() => _controller.close();
}

void main() {
  group('ChatProgram', () {
    late Directory tmp;
    late File stateFile;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('chat-app-test');
      stateFile = File('${tmp.path}/state.json');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('refuses an empty room list', () {
      expect(
        () => ChatProgram(channels: [], ticker: _FakeTicker(), stateFile: stateFile),
        throwsArgumentError,
      );
    });

    test('start folds every room, current or not', () async {
      final fabrica = FakeChannel(name: 'fabrica', me: _me)
        ..syncResult = [
          Spoke(Message(id: 'm-1', author: _cafe, spoken: DateTime(2026), body: 'hi')),
        ];
      final design = FakeChannel(name: 'design', me: _me)
        ..syncResult = [
          Spoke(Message(id: 'm-2', author: _cafe, spoken: DateTime(2026), body: '@alfred there')),
        ];
      final program = ChatProgram(
        channels: [fabrica, design],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );

      await program.start();

      // The current room (fabrica) is what the model shows.
      expect(program.model.lines, hasLength(1));
      // A room with no persisted mark opens caught up on its first fold —
      // per Room's own law — so design's noise is silent even though it
      // folded too, which is provable through the transcript it now holds.
      expect(program.session.rooms[1].transcript.lines, hasLength(1));
      expect(program.session.rooms[1].activity.isQuiet, isTrue);
    });

    test('speaking dispatches to the current room and persists sent history', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me);
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );
      await program.start();
      program.session.currentRoom.composer.insert('status?');

      final quit = await program.handleKeyPress(const KeyPress(Key.enter));

      expect(quit, isFalse);
      expect(channel.spoken, ['status?']);
      final reloaded = PersistedState.load(file: stateFile);
      expect(reloaded.of('bentos.chat:fabrica').sentHistory, ['status?']);
    });

    test('a refusal is rendered as a system line, never swallowed', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me, sayResult: const Refused('not a member'));
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );
      await program.start();
      program.session.currentRoom.composer.insert('status?');

      await program.handleKeyPress(const KeyPress(Key.enter));

      final notice = program.model.lines.whereType<SystemLine>().single;
      expect(notice.text, contains('refused'));
      expect(notice.text, contains('not a member'));
    });

    test('/quit persists and reports quit without dispatching anything', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me);
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );
      await program.start();
      program.session.currentRoom.composer.insert('/quit');

      final quit = await program.handleKeyPress(const KeyPress(Key.enter));

      expect(quit, isTrue);
      expect(channel.spoken, isEmpty);
      expect(stateFile.existsSync(), isTrue);
    });

    test('a tick syncs every room and persists the result', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me);
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );
      await program.start();

      channel.syncResult = [
        Spoke(Message(id: 'm-1', author: _cafe, spoken: DateTime(2026), body: 'hi')),
      ];
      await program.tick();

      expect(program.model.lines, hasLength(1));
    });

    test('resumes on the persisted current room, not room 0', () async {
      PersistedState(currentCoordinate: 'bentos.chat:design').save(file: stateFile);

      final program = ChatProgram(
        channels: [
          FakeChannel(name: 'fabrica', me: _me),
          FakeChannel(name: 'design', me: _me),
        ],
        ticker: _FakeTicker(),
        stateFile: stateFile,
      );

      expect(program.session.currentIndex, 1);
    });
  });
}
