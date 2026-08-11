/// What the person meant — keystrokes into [Intent], plus the composing
/// line. A [KeyPress] is this program's own vocabulary, never the
/// framework's: the render adapter is the one file that reads a raw keyboard
/// event, and translates it into this before it reaches here, which is what
/// keeps this class assertable with no terminal.
library;

import 'composer.dart';
import 'intent.dart';
import 'session.dart';

enum Key {
  char,
  paste,
  enter,
  tab,
  backspace,
  deleteForward,
  left,
  right,
  up,
  down,
  pageUp,
  pageDown,
  home,
  end,
  roomByIndex,
}

final class KeyPress {
  const KeyPress(this.key, {this.char, this.index});

  final Key key;

  /// The typed character, for [Key.char]; the whole block, for [Key.paste] —
  /// nocterm hands a paste over as one event, so it lands in the composer as
  /// one insert rather than one keystroke per character. A newline inside it
  /// is text, never a submit.
  final String? char;

  /// The zero-based room index, for [Key.roomByIndex].
  final int? index;
}

/// A move of the transcript viewport, one line or one page. Named here
/// because [Input] decides *whether* a keypress means "scroll" — `PageUp`
/// always, `Up`/`Down` only while the transcript is focused — without being
/// allowed to act on a viewport it cannot import: that decision leaves the
/// core as this value, and only the render adapter turns it into a call
/// against the framework's scroll controller.
enum ScrollStep { lineUp, lineDown, pageUp, pageDown }

/// What handling one [KeyPress] came to.
final class InputEffect {
  const InputEffect({
    this.intent,
    this.scroll,
    this.quit = false,
    this.persistable = false,
  });

  /// An act for the caller to carry out against the channel.
  final Intent? intent;

  /// A viewport move for the render adapter to carry out — never touched
  /// here, since only it holds the scroll controller. See [ScrollStep].
  final ScrollStep? scroll;

  /// `/quit`, or the framework's own Ctrl+C read as one.
  final bool quit;

  /// True for whatever [persisted_state.dart] keeps — a room switched, a
  /// line sent — never for a character typed or a scroll, which live in
  /// memory only.
  final bool persistable;
}

final class Input {
  const Input();

  InputEffect handle(KeyPress press, Session session) {
    final room = session.currentRoom;
    final composer = room.composer;

    switch (press.key) {
      case Key.tab:
        if (session.focus == Focus.composer) {
          session.focusTranscript();
        } else {
          session.focusComposer();
        }
        return const InputEffect();

      case Key.roomByIndex:
        final index = press.index;
        if (index == null) return const InputEffect();
        session.switchTo(index);
        return const InputEffect(persistable: true);

      case Key.pageUp:
        return const InputEffect(scroll: ScrollStep.pageUp);
      case Key.pageDown:
        return const InputEffect(scroll: ScrollStep.pageDown);

      case Key.up:
        if (session.focus == Focus.transcript) {
          return const InputEffect(scroll: ScrollStep.lineUp);
        }
        composer.historyPrevious();
        return const InputEffect();
      case Key.down:
        if (session.focus == Focus.transcript) {
          return const InputEffect(scroll: ScrollStep.lineDown);
        }
        composer.historyNext();
        return const InputEffect();

      case Key.left:
        composer.moveLeft();
        return const InputEffect();
      case Key.right:
        composer.moveRight();
        return const InputEffect();
      case Key.home:
        composer.moveToStart();
        return const InputEffect();
      case Key.end:
        composer.moveToEnd();
        return const InputEffect();
      case Key.backspace:
        composer.backspace();
        return const InputEffect();
      case Key.deleteForward:
        composer.deleteForward();
        return const InputEffect();

      case Key.char:
      case Key.paste:
        final s = press.char;
        if (s != null) composer.insert(s);
        return const InputEffect();

      case Key.enter:
        return _submit(composer);
    }
  }

  /// Speech is the default and a command is the exception: a line starting
  /// with one `/` is a command, and one starting with `//` is speech that
  /// escapes it — without that, nobody typing a literal slash could say so.
  InputEffect _submit(Composer composer) {
    final text = composer.text;
    if (text.trim().isEmpty) return const InputEffect();

    if (text.startsWith('//')) {
      composer.moveToStart();
      composer.deleteForward();
      return const InputEffect(intent: Speak(), persistable: true);
    }

    if (text.startsWith('/')) {
      final parts = text.substring(1).trim().split(RegExp(r'\s+'));
      final verb = parts.first;
      if (verb == 'quit') return const InputEffect(quit: true);
      // No other verb is wired for v1 — dropped rather than spoken, since a
      // command is the exception and must not leak into the channel as prose.
      return InputEffect(intent: InvokeCommand(verb, parts.skip(1).toList()));
    }

    return const InputEffect(intent: Speak(), persistable: true);
  }
}
