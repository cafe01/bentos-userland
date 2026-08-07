/// Proves the render adapter, not the product: a small suite over
/// [testNocterm]/[TerminalState], the exact counterpart of the framework-free
/// suite over [ScreenModel] itself. Resize cannot be simulated here — that
/// belongs to the hand-drive, not to a test straining to fake it.
library;

import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/app.dart';
import 'package:bentos_userland/src/chat_client/hotlist.dart';
import 'package:bentos_userland/src/chat_client/render/screen_view.dart';
import 'package:bentos_userland/src/chat_client/screen_model.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:bentos_userland/src/chat_client/ticker.dart' as chat show Ticker;
import 'package:bentos_userland/src/chat_client/transcript.dart';
import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import 'fake_channel.dart';

/// A [chat.Ticker] no test here needs to fire — the harness drives its own
/// pumps, and [ChatApp] only reads [chat.Ticker.ticks].
final class _NullTicker implements chat.Ticker {
  @override
  Stream<void> get ticks => const Stream.empty();

  @override
  void nudge() {}

  @override
  void dispose() {}
}

final _alfred = Handle('alfred', 'bentos.life');
final _cafe = Handle('cafe01', 'bentos.life');

Message _msg(String author, String body, {int minute = 0}) => Message(
      id: 'm-$minute-$body',
      author: Handle(author, 'bentos.life'),
      spoken: DateTime(2026, 8, 7, 14, minute),
      body: body,
    );

ScreenModel _model({
  String coordinate = 'bentos.chat:fabrica',
  String? topic = 'the factory floor',
  List<TranscriptLine>? lines,
  int scrollFromBottom = 0,
  int unreadCount = 0,
  int? unreadBoundaryIndex,
  List<Participant> participants = const [],
  String composingText = '',
  int composingCursor = 0,
  Focus focus = Focus.composer,
  List<RoomTab> tabs = const [],
  String? awayReason,
  DateTime? now,
}) {
  return ScreenModel(
    coordinate: coordinate,
    topic: topic,
    lines: lines ?? [SpokenLine(_msg('cafe01', 'status?'))],
    scrollFromBottom: scrollFromBottom,
    unreadCount: unreadCount,
    unreadBoundaryIndex: unreadBoundaryIndex,
    participants: participants,
    composingText: composingText,
    composingCursor: composingCursor,
    me: _alfred,
    awayReason: awayReason,
    now: now ?? DateTime(2026, 8, 7, 14, 32),
    focus: focus,
    tabs: tabs,
    hotlist: const Hotlist([]),
  );
}

void main() {
  test('shows the coordinate and topic in the header', () async {
    await testNocterm('header', (tester) async {
      await tester.pumpComponent(ChatScreenView(model: _model()));
      expect(tester.terminalState, containsText('bentos.chat:fabrica'));
      expect(tester.terminalState, containsText('the factory floor'));
    });
  });

  test('shows a spoken line with its author', () async {
    await testNocterm('spoken line', (tester) async {
      await tester.pumpComponent(ChatScreenView(
        model: _model(lines: [SpokenLine(_msg('cafe01', 'alfred, status?'))]),
      ));
      expect(tester.terminalState, containsText('@cafe01'));
      expect(tester.terminalState, containsText('alfred, status?'));
    });
  });

  test('shows the composing line', () async {
    await testNocterm('composer', (tester) async {
      await tester.pumpComponent(ChatScreenView(
        model: _model(composingText: 'raising the install gate', composingCursor: 25),
      ));
      expect(tester.terminalState, containsText('raising the install gate'));
    });
  });

  test('marks where the unread lines begin', () async {
    await testNocterm('unread marker', (tester) async {
      await tester.pumpComponent(ChatScreenView(
        model: _model(
          lines: [
            SpokenLine(_msg('cafe01', 'old', minute: 1)),
            SpokenLine(_msg('cafe01', 'new one', minute: 2)),
          ],
          unreadCount: 1,
          unreadBoundaryIndex: 1,
        ),
      ));
      final state = tester.terminalState;
      final markerMatch = state.findText('new messages').single;
      final newLineMatch = state.findText('new one').single;
      final oldLineMatch = state.findText('old').first;
      expect(markerMatch.y, lessThan(newLineMatch.y));
      expect(markerMatch.y, greaterThan(oldLineMatch.y));
    });
  });

  test('renders the room bar from the tabs, mentions marked', () async {
    await testNocterm('bar', (tester) async {
      await tester.pumpComponent(ChatScreenView(
        model: _model(tabs: const [
          RoomTab(index: 0, name: 'fabrica', isCurrent: true, activityLevel: ActivityLevel.mention, activityCount: 3),
          RoomTab(index: 1, name: 'design', isCurrent: false, activityLevel: ActivityLevel.none, activityCount: 0),
        ]),
      ));
      expect(tester.terminalState, containsText('[1:fabrica(3!)]'));
      expect(tester.terminalState, containsText('[2:design]'));
    });
  });

  test('the bar shows the clock and presence, here by default', () async {
    await testNocterm('bar presence — here', (tester) async {
      await tester.pumpComponent(ChatScreenView(model: _model(now: DateTime(2026, 8, 7, 14, 32))));
      expect(tester.terminalState, containsText('●here'));
      expect(tester.terminalState, containsText('14:32'));
    });
  });

  test('the bar shows away and the reason, when one was given', () async {
    await testNocterm('bar presence — away', (tester) async {
      await tester.pumpComponent(ChatScreenView(model: _model(awayReason: 'dinner')));
      expect(tester.terminalState, containsText('○away: dinner'));
    });
  });

  test('shows the roster when the terminal is wide enough', () async {
    await testNocterm(
      'roster shown',
      (tester) async {
        await tester.pumpComponent(ChatScreenView(
          model: _model(participants: [Participant(handle: _cafe, joined: DateTime(2026))]),
        ));
        expect(tester.terminalState, containsText('cafe01'));
      },
      size: const Size(80, 24),
    );
  });

  test('hides the roster under the width threshold', () async {
    await testNocterm(
      'roster hidden',
      (tester) async {
        await tester.pumpComponent(ChatScreenView(
          model: _model(lines: const [], participants: [Participant(handle: _cafe, joined: DateTime(2026))]),
        ));
        expect(tester.terminalState, isNot(containsText('cafe01')));
      },
      size: const Size(40, 24),
    );
  });

  group('a real terminal Enter — carries character "\\n", per nocterm\'s own parser', () {
    test('sends typed prose rather than inserting a newline into the composer', () async {
      await testNocterm('enter sends', (tester) async {
        final channel = FakeChannel(name: 'fabrica', me: _alfred);
        final program = ChatProgram(channels: [channel], ticker: _NullTicker());
        await program.start();

        await tester.pumpComponent(ChatApp(program: program));
        await tester.enterText('status?');
        await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.enter, character: '\n'));

        expect(channel.spoken, ['status?']);
        expect(program.session.currentRoom.composer.text, '');
      });
    });

    test('does not leave the input line drawing across several rows', () async {
      await testNocterm('enter does not wrap the input line', (tester) async {
        final channel = FakeChannel(name: 'fabrica', me: _alfred);
        final program = ChatProgram(channels: [channel], ticker: _NullTicker());
        await program.start();

        await tester.pumpComponent(ChatApp(program: program));
        await tester.enterText('h');
        await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.enter, character: '\n'));
        await tester.enterText('i');

        expect(program.session.currentRoom.composer.text, 'i');
      });
    });
  });

  group('paste — nocterm hands it over as a synthetic Ctrl+V, text sitting in its clipboard buffer', () {
    test('lands the whole block in the composer as one insert', () async {
      await testNocterm('paste inserts block', (tester) async {
        final channel = FakeChannel(name: 'fabrica', me: _alfred);
        final program = ChatProgram(channels: [channel], ticker: _NullTicker());
        await program.start();

        await tester.pumpComponent(ChatApp(program: program));
        ClipboardManager.copy('pasted in one go');
        await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyV, modifiers: ModifierKeys(ctrl: true)));

        expect(program.session.currentRoom.composer.text, 'pasted in one go');
      });
    });

    test('an embedded newline is text, never a submit', () async {
      await testNocterm('paste with newline does not submit', (tester) async {
        final channel = FakeChannel(name: 'fabrica', me: _alfred);
        final program = ChatProgram(channels: [channel], ticker: _NullTicker());
        await program.start();

        await tester.pumpComponent(ChatApp(program: program));
        ClipboardManager.copy('first line\nsecond line');
        await tester.sendKeyEvent(const KeyboardEvent(logicalKey: LogicalKey.keyV, modifiers: ModifierKeys(ctrl: true)));

        expect(program.session.currentRoom.composer.text, 'first line\nsecond line');
        expect(channel.spoken.isEmpty, isTrue);
      });
    });
  });

  test('disables the frame-rate limiter on mount — echo latency is the whole demand', () async {
    await testNocterm('no frame throttle', (tester) async {
      final channel = FakeChannel(name: 'fabrica', me: _alfred);
      final program = ChatProgram(channels: [channel], ticker: _NullTicker());
      await program.start();

      await tester.pumpComponent(ChatApp(program: program));

      expect(SchedulerBinding.instance.enableFrameRateLimiting, isFalse);
    });
  });

  test('renders a spoken instant in local time, never in the UTC it was stored in', () async {
    await testNocterm('spoken line — local clock', (tester) async {
      final utc = DateTime.utc(2026, 8, 7, 17, 32);
      await tester.pumpComponent(ChatScreenView(
        model: _model(lines: [
          SpokenLine(Message(id: 'm-1', author: _cafe, spoken: utc, body: 'status?')),
        ]),
      ));
      final localHour = utc.toLocal().hour.toString().padLeft(2, '0');
      final localMinute = utc.toLocal().minute.toString().padLeft(2, '0');
      expect(tester.terminalState, containsText('$localHour:$localMinute'));
    });
  });
}
