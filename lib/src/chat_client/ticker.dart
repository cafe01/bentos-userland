/// When to look again. Live is a cadence, not a promise — the medium is
/// inert and pushes nothing — which is why this sits behind an interface
/// rather than a bare `Timer`: the day dispatch lands, a doorbell
/// implementation replaces the poll and nothing above this learns.
library;

import 'dart:async';

abstract interface class Ticker {
  /// Fires on the cadence, and once more for every [nudge].
  Stream<void> get ticks;

  /// After a local act, so a person sees it land without waiting out the
  /// cadence.
  void nudge();

  void dispose();
}

/// The cadence is a guess, per the design's own admission — two seconds,
/// until a hand-drive says otherwise.
final class PeriodicTicker implements Ticker {
  PeriodicTicker({this.interval = const Duration(seconds: 2)}) {
    _timer = Timer.periodic(interval, (_) => _controller.add(null));
  }

  final Duration interval;
  final StreamController<void> _controller = StreamController<void>.broadcast();
  late final Timer _timer;

  @override
  Stream<void> get ticks => _controller.stream;

  @override
  void nudge() => _controller.add(null);

  @override
  void dispose() {
    _timer.cancel();
    _controller.close();
  }
}
