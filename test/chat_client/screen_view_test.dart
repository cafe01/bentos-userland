/// Proves the render adapter, not the product: a small suite over
/// [testNocterm]/[TerminalState], the exact counterpart of the framework-free
/// suite over [ScreenModel] itself. Resize cannot be simulated here — that
/// belongs to the hand-drive, not to a test straining to fake it.
library;

import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat_client/activity.dart';
import 'package:bentos_userland/src/chat_client/app.dart';
import 'package:bentos_userland/src/chat_client/render/screen_view.dart';
import 'package:bentos_userland/src/chat_client/screen_model.dart';
import 'package:bentos_userland/src/chat_client/session.dart';
import 'package:bentos_userland/src/chat_client/ticker.dart'
    as chat
    show Ticker;
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

  @override
  bool get connected => true;
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
  int unreadCount = 0,
  int? unreadBoundaryIndex,
  List<Participant> participants = const [],
  String composingText = '',
  int composingCursor = 0,
  Focus focus = Focus.composer,
  List<RoomTab> tabs = const [],
  String? awayReason,
  DateTime? now,
  bool dispatchConnected = true,
  bool rosterOverlay = false,
}) {
  return ScreenModel(
    coordinate: coordinate,
    topic: topic,
    lines: lines ?? [SpokenLine(_msg('cafe01', 'status?'))],
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
    rosterOverlay: rosterOverlay,
    dispatchConnected: dispatchConnected,
  );
}

void main() {
  test('shows the coordinate and topic in the header', () async {
    await testNocterm('header', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('bentos.chat:fabrica'));
      expect(tester.terminalState, containsText('the factory floor'));
    });
  });

  test('shows a spoken line with its author', () async {
    await testNocterm('spoken line', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(lines: [SpokenLine(_msg('cafe01', 'alfred, status?'))]),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('@cafe01'));
      expect(tester.terminalState, containsText('alfred, status?'));
    });
  });

  test('shows the composing line', () async {
    await testNocterm('composer', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(
            composingText: 'raising the install gate',
            composingCursor: 25,
          ),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('raising the install gate'));
    });
  });

  test('marks where the unread lines begin', () async {
    await testNocterm('unread marker', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(
            lines: [
              SpokenLine(_msg('cafe01', 'old', minute: 1)),
              SpokenLine(_msg('cafe01', 'new one', minute: 2)),
            ],
            unreadCount: 1,
            unreadBoundaryIndex: 1,
          ),
          scrollController: AutoScrollController(),
        ),
      );
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
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(
            tabs: const [
              RoomTab(
                index: 0,
                name: 'fabrica',
                isCurrent: true,
                activityLevel: ActivityLevel.mention,
                activityCount: 3,
              ),
              RoomTab(
                index: 1,
                name: 'design',
                isCurrent: false,
                activityLevel: ActivityLevel.none,
                activityCount: 0,
              ),
            ],
          ),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('[1:fabrica(3!)]'));
      expect(tester.terminalState, containsText('[2:design]'));
    });
  });

  test('the bar shows the clock and presence, here by default', () async {
    await testNocterm('bar presence — here', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(now: DateTime(2026, 8, 7, 14, 32)),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('●here'));
      expect(tester.terminalState, containsText('14:32'));
    });
  });

  test('the bar shows away and the reason, when one was given', () async {
    await testNocterm('bar presence — away', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(awayReason: 'dinner'),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('○away: dinner'));
    });
  });

  test(
    'a downed doorbell is visible in the bar, and clears once it is back',
    () async {
      await testNocterm('bar — dispatch down', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(dispatchConnected: false),
            scrollController: AutoScrollController(),
          ),
        );
        expect(tester.terminalState, containsText('reconnecting'));

        await tester.pumpComponent(
          ChatScreenView(
            model: _model(dispatchConnected: true),
            scrollController: AutoScrollController(),
          ),
        );
        expect(tester.terminalState, isNot(containsText('reconnecting')));
      });
    },
  );

  test('shows the roster when the terminal is wide enough', () async {
    await testNocterm('roster shown', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(
            participants: [Participant(handle: _cafe, joined: DateTime(2026))],
          ),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, containsText('cafe01'));
    }, size: const Size(80, 24));
  });

  test('hides the roster under the width threshold', () async {
    await testNocterm('roster hidden', (tester) async {
      await tester.pumpComponent(
        ChatScreenView(
          model: _model(
            lines: const [],
            participants: [Participant(handle: _cafe, joined: DateTime(2026))],
          ),
          scrollController: AutoScrollController(),
        ),
      );
      expect(tester.terminalState, isNot(containsText('cafe01')));
    }, size: const Size(40, 24));
  });

  group(
    'a real terminal Enter — carries character "\\n", per nocterm\'s own parser',
    () {
      test(
        'sends typed prose rather than inserting a newline into the composer',
        () async {
          await testNocterm('enter sends', (tester) async {
            final channel = FakeChannel(name: 'fabrica', me: _alfred);
            final program = ChatProgram(
              channels: [channel],
              ticker: _NullTicker(),
              floor: FakeChatFloor(),
              place: '/fake/place',
            );
            await program.start();

            await tester.pumpComponent(ChatApp(program: program));
            await tester.enterText('status?');
            await tester.sendKeyEvent(
              const KeyboardEvent(
                logicalKey: LogicalKey.enter,
                character: '\n',
              ),
            );

            expect(channel.spoken, ['status?']);
            expect(program.session.currentRoom.composer.text, '');
          });
        },
      );

      test(
        'does not leave the input line drawing across several rows',
        () async {
          await testNocterm('enter does not wrap the input line', (
            tester,
          ) async {
            final channel = FakeChannel(name: 'fabrica', me: _alfred);
            final program = ChatProgram(
              channels: [channel],
              ticker: _NullTicker(),
              floor: FakeChatFloor(),
              place: '/fake/place',
            );
            await program.start();

            await tester.pumpComponent(ChatApp(program: program));
            await tester.enterText('h');
            await tester.sendKeyEvent(
              const KeyboardEvent(
                logicalKey: LogicalKey.enter,
                character: '\n',
              ),
            );
            await tester.enterText('i');

            expect(program.session.currentRoom.composer.text, 'i');
          });
        },
      );
    },
  );

  group(
    'paste — nocterm hands it over as a synthetic Ctrl+V, text sitting in its clipboard buffer',
    () {
      test('lands the whole block in the composer as one insert', () async {
        await testNocterm('paste inserts block', (tester) async {
          final channel = FakeChannel(name: 'fabrica', me: _alfred);
          final program = ChatProgram(
            channels: [channel],
            ticker: _NullTicker(),
            floor: FakeChatFloor(),
            place: '/fake/place',
          );
          await program.start();

          await tester.pumpComponent(ChatApp(program: program));
          ClipboardManager.copy('pasted in one go');
          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.keyV,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );

          expect(program.session.currentRoom.composer.text, 'pasted in one go');
        });
      });

      test('an embedded newline is text, never a submit', () async {
        await testNocterm('paste with newline does not submit', (tester) async {
          final channel = FakeChannel(name: 'fabrica', me: _alfred);
          final program = ChatProgram(
            channels: [channel],
            ticker: _NullTicker(),
            floor: FakeChatFloor(),
            place: '/fake/place',
          );
          await program.start();

          await tester.pumpComponent(ChatApp(program: program));
          ClipboardManager.copy('first line\nsecond line');
          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.keyV,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );

          expect(
            program.session.currentRoom.composer.text,
            'first line\nsecond line',
          );
          expect(channel.spoken.isEmpty, isTrue);
        });
      });
    },
  );

  test(
    'a room left behind keeps its own scroll position — one controller per room',
    () async {
      await testNocterm('per-room scroll', (tester) async {
        final fabrica = FakeChannel(name: 'fabrica', me: _alfred);
        fabrica.syncResult = [
          for (var i = 0; i < 40; i++)
            Spoke(_msg('cafe01', 'line $i', minute: i)),
        ];
        final design = FakeChannel(name: 'design', me: _alfred);
        final program = ChatProgram(
          channels: [fabrica, design],
          ticker: _NullTicker(),
          floor: FakeChatFloor(),
          place: '/fake/place',
        );

        // `ChatApp.initState` itself calls `program.start()` — calling it
        // again here would fold `fabrica.syncResult` a second time, since
        // `FakeChannel.sync()` keeps returning it. One extra pump settles
        // that first `start()` before the scroll below relies on the real
        // 40-line history.
        await tester.pumpComponent(ChatApp(program: program));
        await tester.pump();

        await tester.sendKeyEvent(
          const KeyboardEvent(logicalKey: LogicalKey.pageUp),
        );
        // `_onKey` is unawaited from `onKeyEvent`, so the scroll and the
        // resulting rebuild land a pump after the key is dispatched.
        await tester.pump();
        expect(tester.terminalState, containsText('more below'));

        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.digit2,
            character: '2',
            modifiers: ModifierKeys(alt: true),
          ),
        );
        await tester.pump();
        expect(program.session.currentIndex, 1);

        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.digit1,
            character: '1',
            modifiers: ModifierKeys(alt: true),
          ),
        );
        await tester.pump();
        expect(tester.terminalState, containsText('more below'));
      });
    },
  );

  test(
    'disables the frame-rate limiter on mount — echo latency is the whole demand',
    () async {
      await testNocterm('no frame throttle', (tester) async {
        final channel = FakeChannel(name: 'fabrica', me: _alfred);
        final program = ChatProgram(
          channels: [channel],
          ticker: _NullTicker(),
          floor: FakeChatFloor(),
          place: '/fake/place',
        );
        await program.start();

        await tester.pumpComponent(ChatApp(program: program));

        expect(SchedulerBinding.instance.enableFrameRateLimiting, isFalse);
      });
    },
  );

  group('wrapping — the viewport budgets rendered rows, not lines', () {
    test(
      'a message wider than the transcript column wraps without corrupting the bar or the input row',
      () async {
        await testNocterm('wrapping — clean bar and input', (tester) async {
          // 80 wide with a roster shown (>= the 60-column threshold) leaves the
          // transcript column at 66 — narrower than the terminal, and exactly
          // the width every one of these sentences is built to overrun.
          final lines = [
            for (var i = 0; i < 8; i++)
              SpokenLine(
                _msg(
                  'cafe01',
                  'PADLINE$i this is a long sentence written on purpose so that it wraps '
                      'across more than one physical row in a sixty six column transcript.',
                  minute: i,
                ),
              ),
            SpokenLine(
              _msg(
                'alfred',
                'NEWESTMARKER the last word of the newest message',
                minute: 9,
              ),
            ),
          ];
          await tester.pumpComponent(
            ChatScreenView(
              model: _model(
                lines: lines,
                participants: [
                  Participant(handle: _cafe, joined: DateTime(2026)),
                ],
                composingText: 'typing something',
                tabs: const [
                  RoomTab(
                    index: 0,
                    name: 'fabrica',
                    isCurrent: true,
                    activityLevel: ActivityLevel.none,
                    activityCount: 0,
                  ),
                ],
              ),
              scrollController: AutoScrollController(),
            ),
          );

          final state = tester.terminalState;
          // The newest message is what a reader should see at the bottom —
          // the fact no layout theory in this front ever produced on its own.
          expect(state, containsText('NEWESTMARKER'));

          final barY = state.findText('●here').single.y;
          final inputY = state.findText('typing something').single.y;
          // The row order the layout promises: transcript above, bar, then
          // the composer as the very last row.
          expect(inputY, greaterThan(barY));

          final barRow = state.getTextAt(0, barY) ?? '';
          final inputRow = state.getTextAt(0, inputY) ?? '';
          // A wrapped continuation of PADLINE reaching the bar or the input
          // row is exactly the compositing defect this front chased for a
          // day — proven gone by its own absence, not by a clean screenshot.
          expect(barRow, isNot(contains('PADLINE')));
          expect(barRow, contains('[1:fabrica]'));
          expect(inputRow, isNot(contains('PADLINE')));
          // The frame's left edge, then the prompt: the composer owns its
          // row from the first cell inside the border — R5.5.
          expect(inputRow, startsWith('│> '));
        }, size: const Size(80, 24));
      },
    );
  });

  group('the clip — protects the bar even when a single message cannot fit', () {
    test(
      'a message taller than the whole viewport is cut, never bled into the bar',
      () async {
        await testNocterm('clip guard — oversized message', (tester) async {
          // No arithmetic keeps this inside the budget — the message alone
          // is built to need far more rows than a 24-row screen has. This
          // witnesses the guard, not the fix: the cure cannot help here by
          // construction, so only ClipRect stands between this and the bar.
          final giant = [for (var i = 0; i < 400; i++) 'GIANTWORD$i'].join(' ');
          await tester.pumpComponent(
            ChatScreenView(
              model: _model(
                lines: [SpokenLine(_msg('cafe01', giant))],
                tabs: const [
                  RoomTab(
                    index: 0,
                    name: 'fabrica',
                    isCurrent: true,
                    activityLevel: ActivityLevel.none,
                    activityCount: 0,
                  ),
                ],
              ),
              scrollController: AutoScrollController(),
            ),
          );

          final state = tester.terminalState;
          final barY = state.findText('●here').single.y;
          final barRow = state.getTextAt(0, barY) ?? '';
          expect(barRow, isNot(contains('GIANTWORD')));
          expect(barRow, contains('[1:fabrica]'));

          // The composer's row is the last one inside the frame — the
          // bottom border now owns the terminal's final row.
          final inputRow =
              state.getTextAt(0, state.size.height.toInt() - 2) ?? '';
          expect(inputRow, isNot(contains('GIANTWORD')));
          expect(inputRow, startsWith('│> '));
        }, size: const Size(80, 24));
      },
    );
  });

  test(
    'renders a spoken instant in local time, never in the UTC it was stored in',
    () async {
      await testNocterm('spoken line — local clock', (tester) async {
        final utc = DateTime.utc(2026, 8, 7, 17, 32);
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(
              lines: [
                SpokenLine(
                  Message(
                    id: 'm-1',
                    author: _cafe,
                    spoken: utc,
                    body: 'status?',
                  ),
                ),
              ],
            ),
            scrollController: AutoScrollController(),
          ),
        );
        final localHour = utc.toLocal().hour.toString().padLeft(2, '0');
        final localMinute = utc.toLocal().minute.toString().padLeft(2, '0');
        expect(tester.terminalState, containsText('$localHour:$localMinute'));
      });
    },
  );

  group('the frame and the padding — R5.5', () {
    test('one border wraps the program, so nothing sits flush', () async {
      await testNocterm('frame', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(),
            scrollController: AutoScrollController(),
            background: TerminalBackground.dark,
          ),
        );

        final state = tester.terminalState;
        final width = state.size.width.toInt();
        final height = state.size.height.toInt();
        final top = state.getTextAt(0, 0) ?? '';
        final bottom = state.getTextAt(0, height - 1) ?? '';

        expect(top, startsWith('┌'));
        expect(top, endsWith('┐'));
        expect(bottom, startsWith('└'));
        expect(bottom, endsWith('┘'));
        // Every row between the corners is bounded on both sides: no region
        // reaches the terminal's own edge.
        for (var y = 1; y < height - 1; y++) {
          final row = state.getTextAt(0, y) ?? '';
          expect(row[0], '│', reason: 'row $y is flush on the left');
          expect(row[width - 1], '│', reason: 'row $y is flush on the right');
        }
      });
    });

    test('the border is chrome, never a text role', () async {
      await testNocterm('frame — chrome', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(),
            scrollController: AutoScrollController(),
            background: TerminalBackground.dark,
          ),
        );
        final corner = tester.terminalState.getCellAt(0, 0)!;
        expect(corner.char, '┌');
        expect(corner.style.color, const Color(0x5C6370));
      });
    });

    test('the transcript is padded one cell inside the frame', () async {
      await testNocterm('padding', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(lines: [SpokenLine(_msg('cafe01', 'PADDED'))]),
            scrollController: AutoScrollController(),
          ),
        );
        final state = tester.terminalState;
        final match = state.findText('PADDED').single;
        final row = state.getTextAt(0, match.y) ?? '';
        // The frame owns column 0; the padding owns column 1; the
        // transcript's own text begins after it.
        expect(row.substring(0, 2), '│ ');
      });
    });
  });

  group('the roster overlay — R5.8', () {
    final _roster = [
      Participant(handle: _cafe, joined: DateTime(2026)),
      Participant(
        handle: Handle('mariela', 'bentos.life'),
        joined: DateTime(2026),
      ),
    ];

    test('shows the roster whole, in place of the transcript', () async {
      await testNocterm('roster overlay', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(
              rosterOverlay: true,
              participants: _roster,
              lines: [SpokenLine(_msg('cafe01', 'HIDDENSPEECH'))],
            ),
            scrollController: AutoScrollController(),
          ),
        );
        final state = tester.terminalState;
        expect(state, containsText('cafe01'));
        expect(state, containsText('mariela'));
        expect(state, isNot(containsText('HIDDENSPEECH')));
      });
    });

    test('is available at a width that already shows the column', () async {
      await testNocterm('roster overlay — wide', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(
              rosterOverlay: true,
              participants: _roster,
              lines: [SpokenLine(_msg('cafe01', 'HIDDENSPEECH'))],
            ),
            scrollController: AutoScrollController(),
          ),
        );
        // One mechanism, never a second one gated on how narrow the
        // terminal is: at 100 columns the column would have fitted, and the
        // overlay still replaces the transcript.
        expect(tester.terminalState, isNot(containsText('HIDDENSPEECH')));
        expect(tester.terminalState, containsText('mariela'));
      }, size: const Size(100, 24));
    });

    test(
      'Ctrl+R toggles it, and toggling back restores the transcript',
      () async {
        await testNocterm('roster overlay — Ctrl+R', (tester) async {
          final channel = FakeChannel(name: 'fabrica', me: _alfred);
          final program = ChatProgram(
            channels: [channel],
            ticker: _NullTicker(),
            floor: FakeChatFloor(),
            place: '/fake/place',
          );
          await program.start();
          await tester.pumpComponent(ChatApp(program: program));

          expect(program.session.rosterOverlay, isFalse);
          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.keyR,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );
          expect(program.session.rosterOverlay, isTrue);

          await tester.sendKeyEvent(
            const KeyboardEvent(
              logicalKey: LogicalKey.keyR,
              modifiers: ModifierKeys(ctrl: true),
            ),
          );
          expect(program.session.rosterOverlay, isFalse);
        });
      },
    );

    test(
      'a display name too wide for the column cannot paint past it',
      () async {
        await testNocterm('roster — overrun', (tester) async {
          await tester.pumpComponent(
            ChatScreenView(
              model: _model(
                lines: [SpokenLine(_msg('cafe01', 'SPEECHHERE'))],
                participants: [
                  Participant(
                    handle: Handle('ROSTEROVERRUNNINGNAME', 'bentos.life'),
                    joined: DateTime(2026),
                    away: 'AWAYREASONTHATRUNSFARPASTTHECOLUMN',
                  ),
                ],
              ),
              scrollController: AutoScrollController(),
            ),
          );

          final state = tester.terminalState;
          final speechY = state.findText('SPEECHHERE').single.y;
          final speechRow = state.getTextAt(0, speechY) ?? '';
          // The clip is what keeps the roster inside its own column: a name
          // built to overrun its budget is trimmed, never bled into the
          // transcript beside it or through the frame.
          expect(speechRow, isNot(contains('ROSTEROVERRUN')));
          expect(speechRow, endsWith('│'));
          for (var y = 1; y < state.size.height.toInt() - 1; y++) {
            final row = state.getTextAt(0, y) ?? '';
            expect(row, isNot(contains('AWAYREASONTHATRUNSFARPAST')));
          }
        }, size: const Size(80, 24));
      },
    );

    test('a roster longer than the screen cannot paint into the bar', () async {
      await testNocterm('roster — taller than its column', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            model: _model(
              lines: [SpokenLine(_msg('cafe01', 'SPEECHHERE'))],
              participants: [
                for (var i = 0; i < 40; i++)
                  Participant(
                    handle: Handle('member$i', 'bentos.life'),
                    joined: DateTime(2026),
                  ),
              ],
              tabs: const [
                RoomTab(
                  index: 0,
                  name: 'fabrica',
                  isCurrent: true,
                  activityLevel: ActivityLevel.none,
                  activityCount: 0,
                ),
              ],
            ),
            scrollController: AutoScrollController(),
          ),
        );

        // The region is laid out taller than the column it sits in — the
        // exact shape that once painted the transcript straight through the
        // bar. The clip is what stops it, and the bar and the composer's own
        // row are where the damage would show.
        final state = tester.terminalState;
        final barRow = state.getTextAt(0, state.size.height.toInt() - 3) ?? '';
        final inputRow =
            state.getTextAt(0, state.size.height.toInt() - 2) ?? '';
        expect(barRow, contains('[1:fabrica]'));
        expect(barRow, isNot(contains('member')));
        expect(inputRow, startsWith('│> '));
        expect(inputRow, isNot(contains('member')));
      }, size: const Size(80, 24));
    });
  });

  group('which colour table — R5.6', () {
    test('the person\'s own word outranks everything', () {
      expect(
        resolveBackground({'BENTOS_CHAT_THEME': 'light', 'COLORFGBG': '15;0'}),
        TerminalBackground.light,
      );
      expect(
        resolveBackground({'BENTOS_CHAT_THEME': 'DARK ', 'COLORFGBG': '0;15'}),
        TerminalBackground.dark,
      );
    });

    test('COLORFGBG is read where a terminal sets it', () {
      expect(
        resolveBackground({'COLORFGBG': '0;15'}),
        TerminalBackground.light,
      );
      expect(resolveBackground({'COLORFGBG': '15;0'}), TerminalBackground.dark);
      expect(
        resolveBackground({'COLORFGBG': '15;default;0'}),
        TerminalBackground.dark,
      );
    });

    test('anything unstated or unparseable falls to dark, silently', () {
      expect(resolveBackground({}), TerminalBackground.dark);
      expect(resolveBackground({'COLORFGBG': ''}), TerminalBackground.dark);
      expect(
        resolveBackground({'COLORFGBG': '15;default'}),
        TerminalBackground.dark,
      );
      expect(
        resolveBackground({'BENTOS_CHAT_THEME': 'sepia'}),
        TerminalBackground.dark,
      );
    });
  });

  group('a role becomes a colour once — R5.7', () {
    /// The colour actually painted into the cell the text landed in — the
    /// only reading that proves the table reached the screen, rather than
    /// proving the table exists.
    Color colourOf(TerminalState state, String text) {
      final match = state.findText(text).first;
      return state.getCellAt(match.x, match.y)!.style.color!;
    }

    test('two facts of different kinds do not read alike', () async {
      await testNocterm('roles — warning against notice', (tester) async {
        final at = DateTime(2026, 8, 7, 14, 5);
        await tester.pumpComponent(
          ChatScreenView(
            background: TerminalBackground.dark,
            model: _model(
              topic: null,
              lines: [
                SpokenLine(_msg('cafe01', 'SPOKEN', minute: 1)),
                SystemLine('NOTICED', at, kind: SystemLineKind.notice),
                SystemLine('WARNED', at, kind: SystemLineKind.warning),
              ],
            ),
            scrollController: AutoScrollController(),
          ),
        );

        final state = tester.terminalState;
        final spoken = colourOf(state, 'SPOKEN');
        final notice = colourOf(state, 'NOTICED');
        final warning = colourOf(state, 'WARNED');

        expect(spoken.isDefault, isTrue, reason: 'primary is the terminal own');
        expect(notice, isNot(warning));
        expect(warning, const Color(0xFF8B94));
        expect(notice, const Color(0x9299A6));
      });
    });

    test('a mention is the loudest role in the bar', () async {
      await testNocterm('roles — mentioned tab', (tester) async {
        await tester.pumpComponent(
          ChatScreenView(
            background: TerminalBackground.dark,
            model: _model(
              tabs: const [
                RoomTab(
                  index: 0,
                  name: 'fabrica',
                  isCurrent: false,
                  activityLevel: ActivityLevel.mention,
                  activityCount: 3,
                ),
                RoomTab(
                  index: 1,
                  name: 'design',
                  isCurrent: false,
                  activityLevel: ActivityLevel.none,
                  activityCount: 0,
                ),
              ],
            ),
            scrollController: AutoScrollController(),
          ),
        );

        final state = tester.terminalState;
        expect(colourOf(state, '[1:fabrica'), const Color(0xBB86FC));
        expect(colourOf(state, '[2:design'), const Color(0x9299A6));
      });
    });

    test('the same screen paints differently on a light terminal', () async {
      await testNocterm('roles — light table', (tester) async {
        final at = DateTime(2026, 8, 7, 14, 5);
        await tester.pumpComponent(
          ChatScreenView(
            background: TerminalBackground.light,
            model: _model(
              topic: null,
              lines: [SystemLine('WARNED', at, kind: SystemLineKind.warning)],
            ),
            scrollController: AutoScrollController(),
          ),
        );
        // Not the dark table's warning: a colour chosen for one background
        // and reused on the other is exactly what R5.6 refuses.
        expect(colourOf(tester.terminalState, 'WARNED'), const Color(0xB02A20));
      });
    });
  });
}
