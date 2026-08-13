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
const _place = '/fake/place';

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

  @override
  bool get connected => true;
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
        () => ChatProgram(
          channels: [],
          ticker: _FakeTicker(),
          floor: FakeChatFloor(),
          place: _place,
          stateFile: stateFile,
        ),
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
        floor: FakeChatFloor(),
        place: _place,
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
        floor: FakeChatFloor(),
        place: _place,
        stateFile: stateFile,
      );
      await program.start();
      program.session.currentRoom.composer.insert('status?');

      final effect = await program.handleKeyPress(const KeyPress(Key.enter));

      expect(effect.quit, isFalse);
      expect(channel.spoken, ['status?']);
      final reloaded = PersistedState.load(file: stateFile);
      expect(reloaded.of('bentos.chat:fabrica').sentHistory, ['status?']);
    });

    test('a refusal is rendered as a system line, never swallowed', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me, sayResult: const Refused('not a member'));
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        floor: FakeChatFloor(),
        place: _place,
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
        floor: FakeChatFloor(),
        place: _place,
        stateFile: stateFile,
      );
      await program.start();
      program.session.currentRoom.composer.insert('/quit');

      final effect = await program.handleKeyPress(const KeyPress(Key.enter));

      expect(effect.quit, isTrue);
      expect(channel.spoken, isEmpty);
      expect(stateFile.existsSync(), isTrue);
    });

    test('a tick syncs every room and persists the result', () async {
      final channel = FakeChannel(name: 'fabrica', me: _me);
      final program = ChatProgram(
        channels: [channel],
        ticker: _FakeTicker(),
        floor: FakeChatFloor(),
        place: _place,
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
        floor: FakeChatFloor(),
        place: _place,
        stateFile: stateFile,
      );

      expect(program.session.currentIndex, 1);
    });

    group('acting from inside the room — R1', () {
      Future<ChatProgram> _program(FakeChannel channel, {FakeChatFloor? floor}) async {
        final program = ChatProgram(
          channels: [channel],
          ticker: _FakeTicker(),
          floor: floor ?? FakeChatFloor(),
          place: _place,
          stateFile: stateFile,
        );
        await program.start();
        return program;
      }

      Future<void> _type(ChatProgram program, String text) async {
        program.session.currentRoom.composer.insert(text);
        await program.handleKeyPress(const KeyPress(Key.enter));
      }

      test('/join on the current room lands and notices immediately — no ChannelEvent exists for it', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/join');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.notice);
        expect(notice.text, contains('joined'));
      });

      test('/leave lands and notices immediately', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/leave');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.notice);
        expect(notice.text, contains('left'));
      });

      test('/away with a multi-word reason notices immediately, reason included', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/away lunch with the team');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.notice);
        expect(notice.text, contains('lunch with the team'));
      });

      test('/back notices immediately', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/back');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.notice);
      });

      test(
        '/topic <text> lands silently — the coming TopicChanged event is its only rendering, never a duplicate notice',
        () async {
          final channel = FakeChannel(name: 'fabrica', me: _me);
          final program = await _program(channel);

          await _type(program, '/topic the factory floor');

          expect(program.model.lines.whereType<SystemLine>(), isEmpty);
        },
      );

      test('bare /topic reads and prints the current topic', () async {
        final channel = _TopicChannel(name: 'fabrica', me: _me, currentTopic: 'the factory floor');
        final program = await _program(channel);

        await _type(program, '/topic');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.text, contains('the factory floor'));
      });

      test('a refusal on any of the four notice-bearing acts still renders as a warning, not a notice', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        channel.awayResult = const Refused('already away');
        final program = await _program(channel);

        await _type(program, '/away');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.warning);
        expect(notice.text, contains('already away'));
      });

      test('an unrecognized command is reported, never dropped in silence — R2.1', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/mute here');

        final notice = program.model.lines.whereType<SystemLine>().single;
        expect(notice.kind, SystemLineKind.warning);
        expect(notice.text, contains('mute'));
      });

      test('/list reads the floor at the program\'s own place and marks what is already open', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final floor = FakeChatFloor(available: ['fabrica', 'design']);
        final program = await _program(channel, floor: floor);

        await _type(program, '/list');

        final lines = program.model.lines.whereType<SystemLine>().map((l) => l.text).toList();
        expect(lines.any((t) => t.contains('fabrica')), isTrue);
        expect(lines.any((t) => t.contains('design')), isTrue);
      });

      test('/help lists the wired verbs', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/help');

        final text = program.model.lines.whereType<SystemLine>().map((l) => l.text).join('\n');
        for (final verb in ['join', 'leave', 'away', 'back', 'topic']) {
          expect(text, contains(verb));
        }
      });

      test('/help names itself and the bindings that are not commands — R5.9', () async {
        final channel = FakeChannel(name: 'fabrica', me: _me);
        final program = await _program(channel);

        await _type(program, '/help');

        final text = program.model.lines.whereType<SystemLine>().map((l) => l.text).join('\n');
        // The listing is the only place a person learns what the program
        // answers to without reading its source, so what has no slash to
        // discover it by must be named here.
        expect(text, contains('/help'));
        expect(text, contains('/quit'));
        expect(text, contains('Ctrl+R'));
        expect(text, contains('Ctrl+C'));
        expect(text, contains('Alt+1'));
        expect(text, contains('Tab'));
      });
    });

    group('opening a room at runtime — R3, R4.3', () {
      test('/join <coordinate> opens a room not yet in the session and joins it, in one path', () async {
        final fabrica = FakeChannel(name: 'fabrica', me: _me);
        final design = FakeChannel(name: 'design', me: _me);
        final floor = FakeChatFloor(channels: {'design': design});
        final program = ChatProgram(
          channels: [fabrica],
          ticker: _FakeTicker(),
          floor: floor,
          place: _place,
          stateFile: stateFile,
        );
        await program.start();
        expect(program.session.rooms, hasLength(1));

        program.session.currentRoom.composer.insert('/join design');
        await program.handleKeyPress(const KeyPress(Key.enter));

        expect(program.session.rooms, hasLength(2));
        expect(program.session.currentRoom.name, 'design');
        // Opened and entered from the same place every other room in this
        // session resolved from.
        expect(floor.requestedPlaces, contains(_place));
      });

      test('/join <coordinate> on an already-open room switches to it rather than opening a second one', () async {
        final fabrica = FakeChannel(name: 'fabrica', me: _me);
        final design = FakeChannel(name: 'design', me: _me);
        final program = ChatProgram(
          channels: [fabrica, design],
          ticker: _FakeTicker(),
          floor: FakeChatFloor(),
          place: _place,
          stateFile: stateFile,
        );
        await program.start();

        program.session.currentRoom.composer.insert('/join design');
        await program.handleKeyPress(const KeyPress(Key.enter));

        expect(program.session.rooms, hasLength(2));
        expect(program.session.currentRoom.name, 'design');
      });
    });
  });
}

/// A [FakeChannel] whose `topic()` answers something other than null, and
/// whose `away()` can be told to refuse — the base fake covers every other
/// act already; these two extra hooks are only needed by the tests that read
/// or refuse them.
final class _TopicChannel extends FakeChannel {
  _TopicChannel({required super.name, required super.me, this.currentTopic});

  final String? currentTopic;

  @override
  Future<String?> topic({String? at}) async => currentTopic;
}
