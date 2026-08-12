/// The doorbell must survive the one thing `Entity.listen`'s own contract
/// guarantees will eventually happen to it: its stream ending. A fault or a
/// bare close are proven separately, since `Journal.tail` delivers both
/// shapes and a fix that only caught one would still go silent on the other.
library;

import 'dart:async';

import 'package:bentos_userland/src/chat/dispatch_ticker.dart';
import 'package:bentos_userland/src/entity/entity.dart';
import 'package:bentos_userland/src/entity/event.dart';
import 'package:bentos_userland/src/entity/instance.dart';
import 'package:bentos_userland/src/git/model/commit.dart';
import 'package:test/test.dart';

/// Zero-IO by construction — [DispatchTicker] never reads a field, only
/// counts the arrival — so a handle to an entity that was never installed is
/// enough to build one.
Event _fakeEvent() {
  final instance = Instance(Entity('demo.test'), 'x');
  return Event(
    instance: instance,
    noun: 'prompt',
    phase: EventPhase.landed,
    commit: const Commit('deadbeef'),
    parent: const Commit('feedface'),
  );
}

void main() {
  group('DispatchTicker', () {
    test('recovers from a stream fault: goes down visibly, then ticks again',
        () async {
      final opens = <StreamController<Event>>[];
      Stream<Event> open() {
        final controller = StreamController<Event>();
        opens.add(controller);
        return controller.stream;
      }

      final ticker = DispatchTicker.over(
        open,
        settle: const Duration(milliseconds: 5),
        backoff: const [Duration(milliseconds: 20)],
      );
      addTearDown(ticker.dispose);

      expect(ticker.connected, isTrue);
      expect(opens, hasLength(1));

      // The outage must be visible the instant it happens, not on the next
      // cadence — the same nudge that flips the indicator is what a room
      // bar would redraw from.
      final outageTick = ticker.ticks.first;
      opens[0].addError(StateError('journal read fault'));
      await opens[0].close();
      await outageTick.timeout(const Duration(seconds: 2));
      expect(ticker.connected, isFalse);

      // Once the backoff elapses, a fresh subscribe lands — and landing is
      // itself a tick, so a room stays stale for no longer than the
      // reconnect takes, with no dispatch required to prove it is back.
      final recoveryTick = ticker.ticks.first;
      await recoveryTick.timeout(const Duration(seconds: 2));
      expect(ticker.connected, isTrue);
      expect(opens, hasLength(2));
    });

    test('a bare close with no error is exactly as lethal, and also recovers',
        () async {
      final opens = <StreamController<Event>>[];
      Stream<Event> open() {
        final controller = StreamController<Event>();
        opens.add(controller);
        return controller.stream;
      }

      final ticker = DispatchTicker.over(
        open,
        settle: const Duration(milliseconds: 5),
        backoff: const [Duration(milliseconds: 20)],
      );
      addTearDown(ticker.dispose);

      final outageTick = ticker.ticks.first;
      // No error at all — an unexpected clean close, which `onError` alone
      // would miss entirely.
      await opens[0].close();
      await outageTick.timeout(const Duration(seconds: 2));
      expect(ticker.connected, isFalse);

      final recoveryTick = ticker.ticks.first;
      await recoveryTick.timeout(const Duration(seconds: 2));
      expect(ticker.connected, isTrue);
      expect(opens, hasLength(2));
    });

    test('an ordinary occurrence still schedules a settled tick, connected throughout',
        () async {
      final opens = <StreamController<Event>>[];
      Stream<Event> open() {
        final controller = StreamController<Event>();
        opens.add(controller);
        return controller.stream;
      }

      final ticker = DispatchTicker.over(
        open,
        settle: const Duration(milliseconds: 5),
      );
      addTearDown(ticker.dispose);

      final tick = ticker.ticks.first;
      opens[0].add(_fakeEvent());
      await tick.timeout(const Duration(seconds: 2));
      expect(ticker.connected, isTrue);
      expect(opens, hasLength(1));
    });
  });
}
