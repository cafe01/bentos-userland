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
import 'dart:io' show Platform;

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

/// Which of the two colour tables a terminal is painted for.
///
/// nocterm has no adaptive colour and cannot see the background: `Color`
/// carries RGB and a terminal-default sentinel, and nothing anywhere probes
/// what the terminal is painted on. Its own `Colors` constants are a
/// dark-theme palette — `Colors.grey` scores 2.87:1 on white — so R5.6 is
/// discharged by two tuned tables against a *stated* background rather than
/// by one set of hues surviving both.
enum TerminalBackground { light, dark }

/// The one table from [Role] to colour, and the only place in the client a
/// colour is named.
///
/// **`primary` is the terminal's own foreground in both tables** — the one
/// colour that cannot be wrong, and the one the person already chose.
/// **`chrome` is deliberately below the threshold text is held to**, since
/// it paints frame glyphs and never a word: a border that competes with
/// speech is drawn too loud. Violet and red are different hue families on
/// purpose — *you were mentioned* and *the doorbell died* are facts of
/// different kinds, and R5.7 forbids them reading alike.
///
/// Contrast, computed against white and against `#18181C`:
///
/// | role | light | dark |
/// |---|---|---|
/// | secondary | 6.05 | 6.18 |
/// | highlight | 5.70 | 6.68 |
/// | warning | 6.57 | 7.90 |
/// | chrome | 2.87 | 2.93 |
const Map<Role, Color> _lightTable = {
  Role.primary: Color.defaultColor,
  Role.secondary: Color(0x5C6370),
  Role.highlight: Color(0x7C3AED),
  Role.warning: Color(0xB02A20),
  Role.chrome: Color(0x9299A6),
};

const Map<Role, Color> _darkTable = {
  Role.primary: Color.defaultColor,
  Role.secondary: Color(0x9299A6),
  Role.highlight: Color(0xBB86FC),
  Role.warning: Color(0xFF8B94),
  Role.chrome: Color(0x5C6370),
};

/// Which table this terminal reads, from the environment alone.
///
/// `BENTOS_CHAT_THEME` is the person's own word and outranks everything.
/// `COLORFGBG` is a convention several terminals set and many do not —
/// Ghostty does not — so it is a free improvement where present and never a
/// mechanism to rely on; its background is the field after the last `;`,
/// and ANSI 0–6 and 8 are dark. Dark is the default because an unset
/// terminal is far more often dark. **The cost is accepted and stated**: a
/// person on a light terminal who declares nothing reads the dark table
/// silently, at 2.24:1 for a warning, with an environment variable to reach
/// for.
TerminalBackground resolveBackground(Map<String, String> environment) {
  final declared = environment['BENTOS_CHAT_THEME']?.trim().toLowerCase();
  if (declared == 'light') return TerminalBackground.light;
  if (declared == 'dark') return TerminalBackground.dark;

  final fgbg = environment['COLORFGBG'];
  if (fgbg != null && fgbg.contains(';')) {
    final background = int.tryParse(fgbg.split(';').last.trim());
    if (background != null) {
      final dark = background <= 6 || background == 8;
      return dark ? TerminalBackground.dark : TerminalBackground.light;
    }
  }

  return TerminalBackground.dark;
}

/// The palette in force for the subtree — an inherited value so that no
/// component below carries it through a constructor, and so the suite can
/// paint the same screen against either background.
class Palette extends InheritedComponent {
  const Palette({super.key, required this.background, required super.child});

  final TerminalBackground background;

  Color color(Role role) => switch (background) {
    TerminalBackground.light => _lightTable[role]!,
    TerminalBackground.dark => _darkTable[role]!,
  };

  static Palette of(BuildContext context) =>
      context.dependOnInheritedComponentOfExactType<Palette>() ??
      const Palette(background: TerminalBackground.dark, child: SizedBox());

  @override
  bool updateShouldNotify(Palette oldComponent) =>
      background != oldComponent.background;
}

/// A [TextStyle] carrying one role's colour, and nothing chosen at a call
/// site — [FontWeight] stays a separate decision, since weight says
/// *current* and colour says *what kind of thing this is*.
TextStyle _styleOf(BuildContext context, Role role, {FontWeight? weight}) =>
    TextStyle(color: Palette.of(context).color(role), fontWeight: weight);

class ChatScreenView extends StatelessComponent {
  ChatScreenView({
    super.key,
    required this.model,
    required this.scrollController,
    TerminalBackground? background,
  }) : background = background ?? resolveBackground(Platform.environment);

  /// Which colour table this screen paints with. Resolved from the
  /// environment once, at the top, and never re-read below: a component
  /// deciding this for itself is the second answer R5.7 forbids.
  final TerminalBackground background;

  final ScreenModel model;

  /// The current room's own viewport position — one controller per room,
  /// held by [ChatApp] so a room left behind keeps its place. Never this
  /// component's to create: a fresh one here would forget where the reader
  /// was the moment the room they are in gets rebuilt.
  final AutoScrollController scrollController;

  @override
  Component build(BuildContext context) {
    return Palette(
      background: background,
      child: Builder(
        builder: (context) => DecoratedBox(
          // R5.5: one framing border around the whole program, so no region
          // sits flush against the terminal's own edge on every side. Drawn
          // by the framework from the constraints its child respects, never
          // by hand arithmetic — which is what keeps it out of the overflow
          // defect the transcript already carries a guard for.
          decoration: BoxDecoration(
            border: BoxBorder.all(
              color: Palette.of(context).color(Role.chrome),
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
                      return _Pad(
                        child: _Roster(participants: model.participants),
                      );
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
                            color: Palette.of(context).color(Role.chrome),
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
                                child: _Roster(
                                  participants: model.participants,
                                ),
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
        ),
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
          style: _styleOf(context, Role.primary, weight: FontWeight.bold),
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
        color: Palette.of(context).color(Role.secondary),
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
        style: _styleOf(context, Role.primary),
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
            style: _styleOf(context, Role.warning, weight: FontWeight.bold),
          ),
          const Text('  '),
        ],
        Text(
          '${model.me} $dot$presence',
          style: _styleOf(context, Role.primary),
        ),
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
            Role.primary,
            weight: focused ? FontWeight.bold : null,
          ),
        ),
        Expanded(
          child: _CaretText(
            text: model.composingText,
            cursor: model.composingCursor,
            active: focused,
          ),
        ),
      ],
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
    final press = _translate(event);
    if (press == null) return;
    final effect = await component.program.handleKeyPress(press);
    if (effect.quit) {
      shutdownApp();
      return;
    }
    final scroll = effect.scroll;
    if (scroll != null)
      _scroll(
        _controllerFor(component.program.session.currentRoom.coordinate),
        scroll,
      );
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
    return Focusable(
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
    );
  }
}

/// A raw keyboard event, in this program's own vocabulary — null for
/// anything neither typed nor bound to a gesture the client acts on.
KeyPress? _translate(KeyboardEvent event) {
  if (event.isAltPressed) {
    final c = event.character;
    final digit = c == null ? null : int.tryParse(c);
    if (digit != null && digit >= 1 && digit <= 9) {
      return KeyPress(Key.roomByIndex, index: digit - 1);
    }
    return null;
  }

  // A bracketed paste — and, on terminals with no bracketing, several
  // characters that landed in one stdin read from fast typing — arrives from
  // nocterm as this synthetic Ctrl+V, the pasted text sitting in its own
  // clipboard buffer rather than on the event. Reading it back is the same
  // move nocterm's own TextField makes.
  // Ctrl+R shows the roster whole — R5.8. Nothing in this composer does a
  // reverse search, so there is no collision to arbitrate.
  if (event.isControlPressed && event.logicalKey == LogicalKey.keyR) {
    return const KeyPress(Key.toggleRoster);
  }

  if (event.isControlPressed && event.logicalKey == LogicalKey.keyV) {
    final text = ClipboardManager.paste();
    if (text == null || text.isEmpty) return null;
    return KeyPress(Key.paste, char: text);
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
  if (named != null) return named;

  if (!event.isControlPressed && event.character != null) {
    return KeyPress(Key.char, char: event.character);
  }

  return null;
}
