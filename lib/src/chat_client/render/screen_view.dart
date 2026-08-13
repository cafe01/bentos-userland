/// Draws a [ScreenModel], and drives the whole program — the one file that
/// names `nocterm`.
///
/// Everything below `render` — dimensions, colour, glyphs, the drawing
/// cursor — lives here and nowhere else in the client. [ChatScreenView]
/// reads a [ScreenModel] and decides nothing about the conversation: it
/// does not scroll, does not mark read, does not know what a room is.
/// [ChatApp] is the one component that does: it is the only place a raw
/// [KeyboardEvent] is read, translated into [KeyPress] and handed to
/// [ChatProgram] — everything [ChatProgram] itself does is provably
/// testable with no terminal.
library;

import 'dart:async';

import 'package:characters/characters.dart';
import 'package:nocterm/nocterm.dart' hide Key;

import '../../chat/model.dart';
import '../activity.dart';
import '../app.dart';
import '../input.dart';
import '../screen_model.dart';
import '../session.dart';
import '../theme.dart';
import '../transcript.dart';

/// Below this width the roster panel is not worth the columns it costs —
/// geometry deciding, per the demand that the roster is "toggleable, hidden
/// under a width threshold": a measurement, never a wish. A person asking
/// for it back at a width that would show it is a different feature, not
/// this constant moving.
const int _rosterWidthThreshold = 60;

const int _rosterWidth = 14;

/// The one place in the client a colour is named: [Role] to a slot of
/// `nocterm`'s own [TuiThemeData], five lines and no exceptions.
///
/// Which theme is in force is nobody's decision here — [NoctermApp] detects
/// the terminal's real background (OSC 11, then `COLORFGBG`, then macOS
/// appearance, then dark) and publishes the matching [TuiThemeData] through
/// [TuiTheme]. There is no second answer to override, which is what R5.7
/// asks for.
///
/// `highlight` takes the accent slot because it is the palette's loudest;
/// `chrome` takes the slot named for borders and dividers. `failure` takes
/// `error` and not `warning`: the yellow `warning` slot scores 2.64:1 on the
/// light background, which is the failure the old hand-tuned tables had.
///
/// WCAG contrast against each theme's own background — `#18181C` dark,
/// `#FAFAFA` light — those numbers being real rather than assumed, since
/// [NoctermApp] paints that background itself:
///
/// | role | dark | light |
/// |---|---|---|
/// | body | 11.94 | 10.47 |
/// | secondary | 6.97 | 4.63 |
/// | highlight | 8.31 | 4.31 |
/// | failure | 5.35 | 5.17 |
/// | chrome | 6.18 | 4.71 |
Color _colorOf(TuiThemeData theme, Role role) => switch (role) {
  Role.body => theme.onBackground,
  Role.secondary => theme.secondary,
  Role.highlight => theme.primary,
  Role.failure => theme.error,
  Role.chrome => theme.outline,
};

/// A [TextStyle] carrying one role's colour, and nothing chosen at a call
/// site — [FontWeight] stays a separate decision, since weight says
/// *current* and colour says *what kind of thing this is*.
TextStyle _styleOf(BuildContext context, Role role, {FontWeight? weight}) =>
    TextStyle(color: _colorOf(TuiTheme.of(context), role), fontWeight: weight);

class ChatScreenView extends StatelessComponent {
  const ChatScreenView({
    super.key,
    required this.model,
    required this.scrollController,
  });

  final ScreenModel model;

  /// The current room's own viewport position — one controller per room,
  /// held by [ChatApp] so a room left behind keeps its place. Never this
  /// component's to create: a fresh one here would forget where the reader
  /// was the moment the room they are in gets rebuilt.
  final AutoScrollController scrollController;

  @override
  Component build(BuildContext context) {
    return DecoratedBox(
      // R5.5: one framing border around the whole program, so no region
      // sits flush against the terminal's own edge on every side. Drawn
      // by the framework from the constraints its child respects, never
      // by hand arithmetic — which is what keeps it out of the overflow
      // defect the transcript already carries a guard for.
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: _colorOf(TuiTheme.of(context), Role.chrome),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header and bar stay flush against the frame: each is a
          // single line that already carries its own visual weight, and
          // a second cell there buys nothing.
          _Header(model: model),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The roster whole, in place of the transcript — R5.8.
                // Available at every width, never a second mechanism
                // gated on how narrow the terminal is.
                if (model.rosterOverlay) {
                  return _Pad(child: _Roster(participants: model.participants));
                }

                final showRoster =
                    constraints.maxWidth >= _rosterWidthThreshold;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Pad(
                        child: _Transcript(
                          model: model,
                          controller: scrollController,
                        ),
                      ),
                    ),
                    if (showRoster) ...[
                      VerticalDivider(
                        color: _colorOf(TuiTheme.of(context), Role.chrome),
                      ),
                      SizedBox(
                        width: _rosterWidth.toDouble(),
                        // The roster's own clip, sized to its own
                        // column: clipping text trims a line the layout
                        // engine already produced, and does not stop a
                        // row from being laid out taller or wider than
                        // the column it sits in. A long display name is
                        // exactly the shape that once broke the
                        // transcript, one column over.
                        child: ClipRect(
                          child: _Pad(
                            child: _Roster(participants: model.participants),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          _Bar(model: model),
          _InputLine(model: model),
        ],
      ),
    );
  }
}

/// One cell of horizontal padding — spent inside the transcript and the
/// roster, where content runs to a boundary and position alone stops
/// distinguishing regions. Nothing else spends a cell without a sentence
/// beside it saying why.
class _Pad extends StatelessComponent {
  const _Pad({required this.child});

  final Component child;

  @override
  Component build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: child);
}

class _Header extends StatelessComponent {
  const _Header({required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    final topic = model.topic;
    return Row(
      children: [
        Text(
          model.coordinate,
          style: _styleOf(context, Role.body, weight: FontWeight.bold),
        ),
        if (topic != null) ...[
          const Text('  — '),
          Expanded(
            child: Text(
              topic,
              overflow: TextOverflow.clip,
              style: _styleOf(context, Role.secondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// The scrollable buffer — a [ListView] over [ScreenModel.lines], the unread
/// marker spliced in as one more item at [ScreenModel.unreadBoundaryIndex].
/// This component decides nothing about where the viewport sits: [controller]
/// does, following the bottom on its own while the reader has not scrolled
/// away, and answering both keyboard scrolling and the mouse wheel — the
/// wheel needs no wiring here at all, nocterm hit-tests it straight to the
/// mounted [ListView].
class _Transcript extends StatelessComponent {
  const _Transcript({required this.model, required this.controller});

  final ScreenModel model;
  final AutoScrollController controller;

  @override
  Component build(BuildContext context) {
    // `ListView(reverse: true)` places item 0 at the bottom edge, so item 0
    // must be the newest line — the idiom nocterm inherits from Flutter for
    // exactly this shape of list. Walked newest-to-oldest once, with the
    // unread marker spliced in right after the boundary line: that is the
    // "next" item in this direction, since the marker sits above it —
    // toward older lines — when read top to bottom.
    final lines = model.lines;
    final boundary = model.unreadBoundaryIndex;
    final items = <Object>[];
    for (var i = lines.length - 1; i >= 0; i--) {
      items.add(lines[i]);
      if (i == boundary) items.add(_unreadMarker);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            controller: controller,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return item == _unreadMarker
                  ? const _UnreadMarker()
                  : _TranscriptRow(line: item as TranscriptLine);
            },
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => controller.isAutoScrollEnabled
              ? const SizedBox()
              : const _MoreBelowMarker(),
        ),
      ],
    );
  }
}

/// Marks a slot in the newest-to-oldest item list built by [_Transcript] as
/// the unread marker rather than a [TranscriptLine] — an `Object` sentinel
/// instead of a richer type because the list it lives in is transient,
/// built and consumed within one `build()`.
const Object _unreadMarker = Object();

class _UnreadMarker extends StatelessComponent {
  const _UnreadMarker();

  @override
  Component build(BuildContext context) {
    // The unread boundary is *look here* — the same fact a mention is, and
    // therefore the same role, not a second loud colour beside it.
    return Text(
      '─────────────── new messages ───────────────',
      style: _styleOf(context, Role.highlight),
    );
  }
}

class _MoreBelowMarker extends StatelessComponent {
  const _MoreBelowMarker();

  @override
  Component build(BuildContext context) {
    return Text(
      '── more below ──',
      style: TextStyle(
        color: _colorOf(TuiTheme.of(context), Role.secondary),
        reverse: true,
      ),
    );
  }
}

class _TranscriptRow extends StatelessComponent {
  const _TranscriptRow({required this.line});

  final TranscriptLine line;

  @override
  Component build(BuildContext context) {
    // The role comes from the core's own total mapping — a notice and a
    // warning are told apart by `SystemLineKind`, never by reading the text.
    return Text(
      _lineText(line),
      overflow: TextOverflow.clip,
      style: _styleOf(context, roleOfLine(line)),
    );
  }
}

/// The prose one [TranscriptLine] draws — the single place that composes it.
String _lineText(TranscriptLine line) => switch (line) {
  SpokenLine(message: final message) =>
    '${_clock(message.spoken)} @${message.author.local}  ${message.body}',
  TopicLine(topic: final topic, by: final by, at: final at) =>
    '${_clock(at)}  *  ${by.local} changed topic to "$topic"',
  SystemLine(text: final text, at: final at) => '${_clock(at)}  ! $text',
};

String _clock(DateTime at) {
  final local = at.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _Roster extends StatelessComponent {
  const _Roster({required this.participants});

  final List<Participant> participants;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final p in participants) ..._participantRows(context, p)],
    );
  }

  List<Component> _participantRows(BuildContext context, Participant p) {
    final dot = p.isAway ? '○' : '●';
    final rows = <Component>[
      Text(
        '$dot ${p.handle.local}',
        overflow: TextOverflow.clip,
        style: _styleOf(context, Role.body),
      ),
    ];
    final reason = p.away;
    if (reason != null && reason.isNotEmpty) {
      rows.add(
        Text(
          '  away: $reason',
          overflow: TextOverflow.clip,
          style: _styleOf(context, Role.secondary),
        ),
      );
    }
    return rows;
  }
}

/// The hotlist bar — `[1:fabrica(3!)]` — one slot per [ScreenModel.tabs],
/// in stable slot order, then who is speaking under this handle.
class _Bar extends StatelessComponent {
  const _Bar({required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    final away = model.awayReason;
    final dot = away == null ? '●' : '○';
    final presence = away == null
        ? 'here'
        : (away.isEmpty ? 'away' : 'away: $away');
    return Row(
      children: [
        for (final tab in model.tabs) ...[_TabSlot(tab: tab), const Text(' ')],
        const Spacer(),
        if (!model.dispatchConnected) ...[
          Text(
            '⚠ reconnecting',
            style: _styleOf(context, Role.failure, weight: FontWeight.bold),
          ),
          const Text('  '),
        ],
        Text('${model.me} $dot$presence', style: _styleOf(context, Role.body)),
        const Text('  '),
        Text(_clock(model.now), style: _styleOf(context, Role.secondary)),
      ],
    );
  }
}

class _TabSlot extends StatelessComponent {
  const _TabSlot({required this.tab});

  final RoomTab tab;

  @override
  Component build(BuildContext context) {
    final suffix = switch (tab.activityLevel) {
      ActivityLevel.none => '',
      ActivityLevel.speech => '(${tab.activityCount})',
      ActivityLevel.mention => '(${tab.activityCount}!)',
    };
    return Text(
      '[${tab.index + 1}:${tab.name}$suffix]',
      style: _styleOf(
        context,
        roleOfTab(tab),
        weight: tab.isCurrent ? FontWeight.bold : null,
      ),
    );
  }
}

/// The composing line — always the last row, the cursor drawn as a reversed
/// cell rather than relying on the terminal's own cursor, since nothing
/// upstream of this file has wired a real one yet.
class _InputLine extends StatelessComponent {
  const _InputLine({required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    final focused = model.focus == Focus.composer;
    return Row(
      children: [
        Text(
          '> ',
          style: _styleOf(
            context,
            Role.body,
            weight: focused ? FontWeight.bold : null,
          ),
        ),
        Expanded(
          // R5.9: an empty composer says what the program answers to. A
          // function of the text being empty and nothing else — no field on
          // the model, no state anywhere — so it leaves on the first
          // keystroke and R5.10 stays true.
          child: model.composingText.isEmpty
              ? _Hint(active: focused)
              : _CaretText(
                  text: model.composingText,
                  cursor: model.composingCursor,
                  active: focused,
                ),
        ),
      ],
    );
  }
}

/// The empty composer's hint: the caret first, then in secondary the two
/// things the program answers to that a person cannot otherwise discover —
/// the help listing, and the one binding that is not a slash command.
class _Hint extends StatelessComponent {
  const _Hint({required this.active});

  final bool active;

  static const String text = '/help for commands · Ctrl+R for who is here';

  @override
  Component build(BuildContext context) {
    // Cut to the room actually available, rather than left to the
    // framework's clip: measured at 30 columns, an overflowing line keeps
    // its *tail* and loses its head — which drops the caret and starts the
    // hint mid-sentence. The caret's cell is reserved first, and what is
    // left is what the hint may spend.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth.toInt() - 1;
        final shown = room <= 0 ? '' : text.characters.take(room).toString();
        return RichText(
          overflow: TextOverflow.clip,
          text: TextSpan(
            children: [
              // The caret keeps the composer's own first cell. The hint
              // sits after it and never moves it.
              TextSpan(
                text: ' ',
                style: active ? const TextStyle(reverse: true) : null,
              ),
              TextSpan(text: shown, style: _styleOf(context, Role.secondary)),
            ],
          ),
        );
      },
    );
  }
}

class _CaretText extends StatelessComponent {
  const _CaretText({
    required this.text,
    required this.cursor,
    required this.active,
  });

  final String text;
  final int cursor;
  final bool active;

  @override
  Component build(BuildContext context) {
    if (!active) return Text(text, overflow: TextOverflow.clip);

    final clusters = text.characters.toList();
    final before = clusters.take(cursor).join();
    final atCursor = cursor < clusters.length ? clusters[cursor] : ' ';
    final after = cursor < clusters.length
        ? clusters.skip(cursor + 1).join()
        : '';

    return RichText(
      overflow: TextOverflow.clip,
      text: TextSpan(
        children: [
          TextSpan(text: before),
          TextSpan(text: atCursor, style: const TextStyle(reverse: true)),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

/// The whole program, mounted with [runApp]: [ChatScreenView] over a live
/// [ChatProgram], the ticker wired to a rebuild, the keyboard wired to
/// [Input].
class ChatApp extends StatefulComponent {
  const ChatApp({super.key, required this.program});

  final ChatProgram program;

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  StreamSubscription<void>? _ticks;

  @override
  void initState() {
    super.initState();
    // This client animates nothing at a fixed rate — it echoes keystrokes,
    // and echo latency is the whole demand. nocterm's default throttles
    // every frame to ~33ms (30fps) regardless of how fast a frame actually
    // renders, which against ordinary typing cadence turns into a felt lag
    // on almost every character (measured: ~24ms median, ~34ms worst case,
    // independent of history size — dropping to ~1ms once disabled).
    SchedulerBinding.instance.enableFrameRateLimiting = false;
    unawaited(
      component.program.start().then((_) {
        if (mounted) setState(() {});
      }),
    );
    _ticks = component.program.ticker.ticks.listen((_) async {
      await component.program.tick();
      if (mounted) setState(() {});
    });
  }

  /// One [AutoScrollController] per room, coordinate-keyed — the only place
  /// nocterm may be named, so the only place this state can live. A room
  /// left behind keeps its own controller, and with it its own place, for
  /// as long as this app runs.
  final Map<String, AutoScrollController> _scrollControllers = {};

  AutoScrollController _controllerFor(String coordinate) =>
      _scrollControllers.putIfAbsent(coordinate, AutoScrollController.new);

  @override
  void dispose() {
    _ticks?.cancel();
    component.program.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _onKey(KeyboardEvent event) async {
    // One event can be several presses: see [_translate]. Applied in order,
    // each awaited, since a submit in the middle of a block must reach the
    // channel before the line after it is typed.
    for (final press in _translate(event)) {
      final effect = await component.program.handleKeyPress(press);
      if (effect.quit) {
        shutdownApp();
        return;
      }
      final scroll = effect.scroll;
      if (scroll != null) {
        _scroll(
          _controllerFor(component.program.session.currentRoom.coordinate),
          scroll,
        );
      }
    }
    if (mounted) setState(() {});
  }

  void _scroll(AutoScrollController controller, ScrollStep step) {
    // `reverse: true` puts the newest line at offset 0, so *up* — toward
    // older lines — is *growing* offset: the controller's own `scrollUp`
    // shrinks it and would move the wrong way. This inverts exactly the way
    // nocterm's own mouse-wheel handler does for a reversed `ListView`
    // (`RenderListViewport.handleMouseWheel`), so the keyboard and the wheel
    // agree.
    switch (step) {
      case ScrollStep.lineUp:
        controller.scrollDown(1);
      case ScrollStep.lineDown:
        controller.scrollUp(1);
      case ScrollStep.pageUp:
        controller.scrollDown(controller.viewportDimension);
      case ScrollStep.pageDown:
        controller.scrollUp(controller.viewportDimension);
    }
  }

  @override
  Component build(BuildContext context) {
    // No `theme` argument: left null, [NoctermApp] asks the terminal what it
    // is painted on (OSC 11, then `COLORFGBG`, then macOS appearance, then
    // dark) and publishes the answer through [TuiTheme] for [_colorOf] to
    // read. Detection is asynchronous, so the first frames carry no theme at
    // all and `TuiTheme.of` falls back to `TuiThemeData.dark` — which is
    // also why a [ChatScreenView] built with no ancestor at all, as the
    // suite builds it, paints in the dark theme rather than failing.
    return NoctermApp(
      child: Focusable(
        focused: true,
        onKeyEvent: (event) {
          // Nocterm offers Ctrl+C to the tree first. Taken here rather than
          // left to fall through, so a quit always goes through the same
          // clean shutdown as `/quit`.
          if (event.isControlPressed && event.logicalKey == LogicalKey.keyC) {
            shutdownApp();
            return true;
          }
          unawaited(_onKey(event));
          return true;
        },
        child: ChatScreenView(
          model: component.program.model,
          scrollController: _controllerFor(
            component.program.session.currentRoom.coordinate,
          ),
        ),
      ),
    );
  }
}

/// A raw keyboard event, in this program's own vocabulary — empty for
/// anything neither typed nor bound to a gesture the client acts on, and more
/// than one press for a block that carries newlines. See [_splitBlock].
List<KeyPress> _translate(KeyboardEvent event) {
  if (event.isAltPressed) {
    final c = event.character;
    final digit = c == null ? null : int.tryParse(c);
    if (digit != null && digit >= 1 && digit <= 9) {
      return [KeyPress(Key.roomByIndex, index: digit - 1)];
    }
    return const [];
  }

  // A bracketed paste — and, on terminals with no bracketing, several
  // characters that landed in one stdin read from fast typing — arrives from
  // nocterm as this synthetic Ctrl+V, the pasted text sitting in its own
  // clipboard buffer rather than on the event. Reading it back is the same
  // move nocterm's own TextField makes.
  // Ctrl+R shows the roster whole — R5.8. Nothing in this composer does a
  // reverse search, so there is no collision to arbitrate.
  if (event.isControlPressed && event.logicalKey == LogicalKey.keyR) {
    return const [KeyPress(Key.toggleRoster)];
  }

  if (event.isControlPressed && event.logicalKey == LogicalKey.keyV) {
    final text = ClipboardManager.paste();
    if (text == null || text.isEmpty) return const [];
    return _splitBlock(text);
  }

  final named = switch (event.logicalKey) {
    LogicalKey.enter => const KeyPress(Key.enter),
    LogicalKey.tab => const KeyPress(Key.tab),
    LogicalKey.backspace => const KeyPress(Key.backspace),
    LogicalKey.delete => const KeyPress(Key.deleteForward),
    LogicalKey.arrowLeft => const KeyPress(Key.left),
    LogicalKey.arrowRight => const KeyPress(Key.right),
    LogicalKey.arrowUp => const KeyPress(Key.up),
    LogicalKey.arrowDown => const KeyPress(Key.down),
    LogicalKey.pageUp => const KeyPress(Key.pageUp),
    LogicalKey.pageDown => const KeyPress(Key.pageDown),
    LogicalKey.home => const KeyPress(Key.home),
    LogicalKey.end => const KeyPress(Key.end),
    _ => null,
  };
  if (named != null) return [named];

  if (!event.isControlPressed && event.character != null) {
    return [KeyPress(Key.char, char: event.character)];
  }

  return const [];
}

/// A newline inside an arriving block **is** an Enter, and the block splits
/// into a line typed, a line sent, a line typed.
///
/// ## Why this exists — the upstream cause
///
/// This is a workaround for a defect in `nocterm` (Norbert515/nocterm, 0.8.0),
/// which is not ours. Two of its facts meet:
///
///  1. `input_parser.dart` gives Enter `character: '\n'` and no modifiers.
///  2. `terminal_binding.dart`'s **`_batchCharacterEvents`** calls any event
///     with a character and no ctrl/alt/meta *printable*, and folds a run of
///     printables into one synthetic paste.
///
/// So whenever Enter lands in the same stdin read as any other event, the
/// binding swallows it into a paste and the client never sees a `LogicalKey.
/// enter` at all. A real terminal coalesces reads constantly — the screen
/// redraws on every keystroke, and bytes typed during that redraw are read
/// together with the CR behind them. The symptom is that a person types a
/// line, presses Enter, and nothing is sent.
///
/// **When `_batchCharacterEvents` stops classifying Enter as printable, this
/// function and the list return of [_translate] can go.** Delete them, and
/// keep the file's byte-level test — it is what would notice a regression.
///
/// ## Why splitting is also simply right
///
/// The cure costs nothing it should not, because [Composer] is single-line by
/// construction: one flat run of grapheme clusters, one cursor, no notion of a
/// row, rendered on one screen line. It cannot hold a multi-line value, so a
/// newline stored in it was never text a reader could edit or see — it was an
/// unrepresentable value being kept. Splitting is what a person pasting three
/// lines into a one-line composer expects anyway: the same three utterances
/// they would have got by typing them.
List<KeyPress> _splitBlock(String text) {
  // A terminal may deliver a paste with CR, CRLF or LF line endings; the
  // batched-Enter path above always arrives as LF. All three mean the same.
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');

  final presses = <KeyPress>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isNotEmpty) presses.add(KeyPress(Key.paste, char: lines[i]));
    // Every separator between lines is one Enter; a trailing newline is a
    // separator too, which is what sends the last line.
    if (i < lines.length - 1) presses.add(const KeyPress(Key.enter));
  }
  return presses;
}
