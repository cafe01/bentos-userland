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
import '../transcript.dart';

/// Below this width the roster panel is not worth the columns it costs —
/// geometry deciding, per the demand that the roster is "toggleable, hidden
/// under a width threshold": a measurement, never a wish. A person asking
/// for it back at a width that would show it is a different feature, not
/// this constant moving.
const int _rosterWidthThreshold = 60;

const int _rosterWidth = 14;

class ChatScreenView extends StatelessComponent {
  const ChatScreenView({super.key, required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(model: model),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showRoster = constraints.maxWidth >= _rosterWidthThreshold;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Transcript(model: model)),
                  if (showRoster)
                    SizedBox(
                      width: _rosterWidth.toDouble(),
                      child: _Roster(participants: model.participants),
                    ),
                ],
              );
            },
          ),
        ),
        _Bar(model: model),
        _InputLine(model: model),
      ],
    );
  }
}

class _Header extends StatelessComponent {
  const _Header({required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    final topic = model.topic;
    return Row(
      children: [
        Text(model.coordinate, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (topic != null) ...[
          const Text('  — '),
          Expanded(
            child: Text(
              topic,
              overflow: TextOverflow.clip,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ],
    );
  }
}

/// The scrollable buffer, sliced from [ScreenModel.lines] at
/// [ScreenModel.scrollFromBottom] — the offset [Transcript] already
/// computed. This component does not decide where the view sits, only how
/// many rows fit and how a line becomes text.
class _Transcript extends StatelessComponent {
  const _Transcript({required this.model});

  final ScreenModel model;

  @override
  Component build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolledAway = model.scrollFromBottom > 0;
        final rows = constraints.maxHeight.isFinite
            ? constraints.maxHeight.floor() - (scrolledAway ? 1 : 0)
            : model.lines.length;
        final visible = _visibleWindow(model.lines, model.scrollFromBottom, rows.clamp(0, 1 << 30));
        final boundary = model.unreadBoundaryIndex;

        final rowWidgets = <Component>[];
        for (var i = visible.start; i < visible.end; i++) {
          if (i == boundary) rowWidgets.add(const _UnreadMarker());
          rowWidgets.add(_TranscriptRow(line: model.lines[i]));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rowWidgets),
            ),
            if (scrolledAway) const _MoreBelowMarker(),
          ],
        );
      },
    );
  }
}

/// The window of [lines] a viewport of [rows] shows when its bottom edge
/// sits [scrollFromBottom] lines back from the end — the same offset
/// [Transcript.append] grows while a reader is scrolled away, so the lines
/// already on screen stay exactly where they were.
({int start, int end}) _visibleWindow(List<TranscriptLine> lines, int scrollFromBottom, int rows) {
  final end = (lines.length - scrollFromBottom).clamp(0, lines.length);
  final start = (end - rows).clamp(0, end);
  return (start: start, end: end);
}

class _UnreadMarker extends StatelessComponent {
  const _UnreadMarker();

  @override
  Component build(BuildContext context) {
    return const Text(
      '─────────────── new messages ───────────────',
      style: TextStyle(color: Colors.yellow),
    );
  }
}

class _MoreBelowMarker extends StatelessComponent {
  const _MoreBelowMarker();

  @override
  Component build(BuildContext context) {
    return const Text(
      '── more below ──',
      style: TextStyle(color: Colors.grey, reverse: true),
    );
  }
}

class _TranscriptRow extends StatelessComponent {
  const _TranscriptRow({required this.line});

  final TranscriptLine line;

  @override
  Component build(BuildContext context) {
    return switch (line) {
      SpokenLine(message: final message) => Text(
          '${_clock(message.spoken)} @${message.author.local}  ${message.body}',
          overflow: TextOverflow.clip,
        ),
      TopicLine(topic: final topic, by: final by, at: final at) => Text(
          '${_clock(at)}  *  ${by.local} changed topic to "$topic"',
          overflow: TextOverflow.clip,
          style: const TextStyle(color: Colors.grey),
        ),
      SystemLine(text: final text, at: final at) => Text(
          '${_clock(at)}  ! $text',
          overflow: TextOverflow.clip,
          style: const TextStyle(color: Colors.yellow),
        ),
    };
  }
}

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
      children: [
        for (final p in participants) ..._participantRows(p),
      ],
    );
  }

  List<Component> _participantRows(Participant p) {
    final dot = p.isAway ? '○' : '●';
    final rows = <Component>[
      Text('$dot ${p.handle.local}', overflow: TextOverflow.clip),
    ];
    final reason = p.away;
    if (reason != null && reason.isNotEmpty) {
      rows.add(Text('  away: $reason', overflow: TextOverflow.clip, style: const TextStyle(color: Colors.grey)));
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
    final presence = away == null ? 'here' : (away.isEmpty ? 'away' : 'away: $away');
    return Row(
      children: [
        for (final tab in model.tabs) ...[_TabSlot(tab: tab), const Text(' ')],
        const Spacer(),
        Text('${model.me} $dot$presence'),
        const Text('  '),
        Text(_clock(model.now)),
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
      style: TextStyle(
        fontWeight: tab.isCurrent ? FontWeight.bold : null,
        color: tab.activityLevel == ActivityLevel.mention ? Colors.yellow : null,
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
        Text('> ', style: TextStyle(fontWeight: focused ? FontWeight.bold : null)),
        Expanded(child: _CaretText(text: model.composingText, cursor: model.composingCursor, active: focused)),
      ],
    );
  }
}

class _CaretText extends StatelessComponent {
  const _CaretText({required this.text, required this.cursor, required this.active});

  final String text;
  final int cursor;
  final bool active;

  @override
  Component build(BuildContext context) {
    if (!active) return Text(text, overflow: TextOverflow.clip);

    final clusters = text.characters.toList();
    final before = clusters.take(cursor).join();
    final atCursor = cursor < clusters.length ? clusters[cursor] : ' ';
    final after = cursor < clusters.length ? clusters.skip(cursor + 1).join() : '';

    return RichText(
      overflow: TextOverflow.clip,
      text: TextSpan(children: [
        TextSpan(text: before),
        TextSpan(text: atCursor, style: const TextStyle(reverse: true)),
        TextSpan(text: after),
      ]),
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
    unawaited(component.program.start().then((_) {
      if (mounted) setState(() {});
    }));
    _ticks = component.program.ticker.ticks.listen((_) async {
      await component.program.tick();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticks?.cancel();
    component.program.dispose();
    super.dispose();
  }

  Future<void> _onKey(KeyboardEvent event) async {
    final press = _translate(event);
    if (press == null) return;
    final quit = await component.program.handleKeyPress(press);
    if (quit) {
      shutdownApp();
      return;
    }
    if (mounted) setState(() {});
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
      child: ChatScreenView(model: component.program.model),
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
