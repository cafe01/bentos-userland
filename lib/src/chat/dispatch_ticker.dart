/// The doorbell: a [Ticker] over the installation's own dispatch, replacing
/// the poll `ticker.dart` named as its own frontier.
library;

import 'dart:async';
import 'dart:io';

import '../entity/entity.dart';
import '../entity/event.dart';
import '../chat_client/ticker.dart';

/// Fires on every occurrence this installation dispatches — **coalesced**,
/// never one tick per occurrence.
///
/// A tick means *look again*, and a burst of real activity — several
/// messages landing together, or the replay `Entity.listen` opens with —
/// warrants exactly one look, not one per line. So every occurrence inside
/// [settle] of the first is folded into the same tick, the same burst-window
/// shape `bentos.chat monitor --wait` already uses.
///
/// **A fresh subscribe starts at the live tip, not genesis.** `Entity.listen`
/// with no `since` opens at the journal's current end — only occurrences
/// after that call are seen — so the class this doc used to describe, one
/// that had to tame a full replay on every reconnect, no longer exists. What
/// [settle] still earns its keep on is the ordinary case: several occurrences
/// landing together warrant one look, not one per line.
///
/// **The stream can die, and the doorbell must not die with it.**
/// `Entity.listen`'s own contract ends its stream on the first fault — a
/// `JournalGap`, a torn read, anything — closing for good rather than
/// skipping past the bad line. Left alone that is a doorbell silent forever
/// after one transient error, with nothing but a stderr line a full-screen
/// terminal never shows: a room that looks current while it has gone deaf.
/// So every stream end — error or a bare close, since the journal's own
/// reader closes its controller in a `finally` either way — is followed by a
/// fresh subscribe after a wait that widens on repeated failure and resets
/// the moment one lands. Reconnecting opens with no `since` on purpose: a
/// fresh `Entity.listen` starts at the tip rather than resuming a cursor this
/// reader never kept, and it is what makes a `JournalGap` harmless to this
/// reader specifically — nothing here consumes the stream for its content,
/// only for *look again*, and the program's own `tick` resyncs from git
/// rather than from the delta it missed.
final class DispatchTicker implements Ticker {
  DispatchTicker(Entity entity, {Duration settle = const Duration(milliseconds: 300)})
      : this._(() => entity.listen({EventPattern.parse('*.landed')}), settle);

  /// The same doorbell over a caller-supplied stream instead of a real
  /// entity's — the seam a test needs to drive a disconnect and a recovery
  /// on demand, with no git journal to fault.
  DispatchTicker.over(
    Stream<Event> Function() open, {
    Duration settle = const Duration(milliseconds: 300),
    List<Duration> backoff = _defaultBackoff,
  }) : this._(open, settle, backoff);

  DispatchTicker._(this._open, this.settle, [this._backoff = _defaultBackoff]) {
    _connect();
  }

  /// How long to wait before a fresh subscribe after the stream ends —
  /// widening on each consecutive failure so a journal that stays broken is
  /// never hammered, capped at the list's last entry rather than growing
  /// without bound.
  static const List<Duration> _defaultBackoff = [
    Duration(milliseconds: 500),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  final Stream<Event> Function() _open;
  final Duration settle;
  final List<Duration> _backoff;

  final StreamController<void> _controller = StreamController<void>.broadcast();
  StreamSubscription<Event>? _sub;
  Timer? _settleTimer;
  Timer? _reconnectTimer;
  int _failures = 0;
  // Optimistic until proven otherwise: the constructor's own first
  // `_connect` must not read as "recovering" and fire a spurious nudge
  // before the program has even called `start`.
  bool _connected = true;
  bool _disposed = false;

  @override
  Stream<void> get ticks => _controller.stream;

  @override
  bool get connected => _connected;

  @override
  void nudge() {
    if (!_controller.isClosed) _controller.add(null);
  }

  void _connect() {
    _reconnectTimer = null;
    final recovering = _failures > 0 || !_connected;
    _sub = _open().listen(
      (_) => _schedule(),
      onError: (Object error) {
        stderr.writeln('chat: dispatch: $error');
        _reconnect();
      },
      onDone: _reconnect,
    );
    _connected = true;
    _failures = 0;
    // A resubscribe after a real outage owes two things at once: the room
    // must resync past whatever it missed, and the outage must stop
    // reading as current. `ChatProgram.tick` does both from one nudge — it
    // re-reads state from git rather than the stream, so this single tick
    // recovers the content and the indicator together.
    if (recovering) nudge();
  }

  /// One stream end, however it happened, is one reconnect in flight —
  /// `Journal.tail` delivers `onError` then `onDone` for the same fault, and
  /// scheduling twice would only race two identical subscribes.
  void _reconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _connected = false;
    nudge();
    final wait = _backoff[_failures.clamp(0, _backoff.length - 1)];
    _failures++;
    _reconnectTimer = Timer(wait, _connect);
  }

  void _schedule() {
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, nudge);
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_sub?.cancel());
    _controller.close();
  }
}
