/// `monitor --wait` — the agent path. Fast, in-process claims over the fake
/// floor: the window, the timeout, the mention predicate. What this file
/// cannot prove — that the cursor survives a real process exiting — is
/// [material/monitor_wait_material_test.dart]'s job, and only that gate's.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:test/test.dart';

import 'face_test.dart' show FakeFloor, Run;
import 'support/doubles.dart' show FakeTicker;

void main() {
  late FakeFloor floor;
  late Directory stateDir;
  late File cursorFile;

  setUp(() {
    floor = FakeFloor();
    stateDir = Directory.systemTemp.createTempSync('monitor-wait-');
    cursorFile = File('${stateDir.path}/monitor-state.json');
  });

  tearDown(() => stateDir.deleteSync(recursive: true));

  Future<Run> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final face = ChatRunner(
      out: out,
      err: err,
      currentDirectory: '/campus',
      environment: const {},
      readStdin: () async => '',
      floor: floor,
      monitorCursorFile: cursorFile,
    );
    await face.run(args);
    return Run(face.exitCode, out.toString(), err.toString());
  }

  Future<void> seated() => run(['join']).then((_) {});

  group('the timeout', () {
    test('nothing landing exits 6, not 0, and never by parsing output',
        () async {
      final result =
          await run(['monitor', '--wait', '--timeout', '0.2', '--interval', '0.05']);

      expect(result.exitCode, 6);
      expect(result.out, isEmpty);
      expect(result.err, contains('timed out'));
    });

    test('--timeout without --wait is a usage error', () async {
      final result = await run(['monitor', '--timeout', '0.2']);

      expect(result.exitCode, 64);
      expect(result.err, contains('--timeout'));
    });
  });

  group('the burst window', () {
    test('opens on the first qualifying event and returns everything drained '
        'while it is open, not one waking per line', () async {
      await seated();

      // Land two messages *before* the wait call starts polling, so the very
      // first `sync()` inside the window already sees both — proving the
      // return is the whole burst and not the first event alone.
      await run(['say', 'first']);
      await run(['say', 'second']);

      final result = await run(
        ['monitor', '--wait', '--timeout', '5', '--interval', '0.05'],
      );

      expect(result.exitCode, 0);
      expect('first'.allMatches(result.out), hasLength(1));
      expect('second'.allMatches(result.out), hasLength(1));
    });

    test('a second --wait call sees nothing new and times out — the first '
        'call\'s batch is not replayed', () async {
      await seated();
      await run(['say', 'first']);

      final landed = await run(
        ['monitor', '--wait', '--timeout', '5', '--interval', '0.05'],
      );
      expect(landed.exitCode, 0);
      expect(landed.out, contains('first'));

      final again = await run(
        ['monitor', '--wait', '--timeout', '0.2', '--interval', '0.05'],
      );
      expect(again.exitCode, 6);
      expect(again.out, isEmpty);
    });

    test('the very first call for a channel sees the whole prior log, per '
        "Channel.sync's own contract for a cursor opened at nothing",
        () async {
      await seated();
      await run(['say', 'said before anybody watched']);

      final result = await run(
        ['monitor', '--wait', '--timeout', '5', '--interval', '0.05'],
      );

      expect(result.exitCode, 0);
      expect(result.out, contains('said before anybody watched'));
    });
  });

  group('--mention', () {
    test('a message that does not name me never opens the window', () async {
      await seated();
      await run(['say', 'just chatting']);

      final result = await run(
        ['monitor', '--wait', '--mention', '--timeout', '0.2', '--interval', '0.05'],
      );

      expect(result.exitCode, 6);
      expect(result.out, isEmpty);
    });

    test('naming me opens it, and the batch is the mentioning message',
        () async {
      await seated();
      await run(['say', '@alfred status?']);

      final result = await run(
        ['monitor', '--wait', '--mention', '--timeout', '5', '--interval', '0.05'],
      );

      expect(result.exitCode, 0);
      expect(result.out, contains('@alfred status?'));
    });
  });

  group('persistence', () {
    test('the cursor is written to the given file, keyed by coordinate',
        () async {
      await seated();
      await run(['say', 'hello']);

      await run(['monitor', '--wait', '--timeout', '5', '--interval', '0.05']);

      final json = jsonDecode(cursorFile.readAsStringSync()) as Map;
      final cursors = json['cursors'] as Map;
      expect(cursors.keys, contains('bentos.chat:fabrica'));
    });
  });

  group('the doorbell', () {
    // Every test above drives the default `_NoopTicker`, whose `ticks` never
    // fires — proving the timeout and the burst window, never a real wake.
    // This group is the one that proves the wait actually answers to a tick.

    test('a dispatch tick wakes the wait, and nothing but a tick ever does',
        () async {
      await seated();
      // Drains the join itself, so the batch the real assertion sees below
      // is purely what the doorbell wakes it for, not this setup's own
      // event.
      await run(['monitor', '--wait', '--timeout', '0.1']);

      final ticker = FakeTicker();
      floor.ticker = ticker;

      // No --timeout: with nothing landed and no tick, this waits forever —
      // bounding it below is what proves the tick is what ends it, not a
      // cadence a poll-based wait would still have found it on.
      final pending = run(['monitor', '--wait']);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await run(['say', 'woke by the doorbell']);
      ticker.tick();

      // The mandatory burst-settle window (1s) still applies after the
      // tick — this bound clears that comfortably while staying well under
      // the 2s a poll on the default `--interval` would have taken to
      // notice the same message.
      final result = await pending.timeout(const Duration(milliseconds: 1300));
      expect(result.exitCode, 0);
      expect(result.out, contains('woke by the doorbell'));
    });

    test(
        'a dispatch outage is reported on stderr, never stdout, and ends '
        'the wait without riding out the wall clock', () async {
      // Unseated on purpose: an unborn channel yields nothing from `sync`,
      // so the only thing this run can possibly end on is the outage or the
      // timeout — and the outage, reported at 20ms, must win over a 300ms
      // wall clock rather than hide behind it until it elapses.
      final ticker = FakeTicker();
      floor.ticker = ticker;

      final pending = run(['monitor', '--wait', '--timeout', '0.3']);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      ticker.connected = false;
      ticker.tick(); // the same nudge a real reconnect fires on going down

      final result = await pending.timeout(const Duration(seconds: 2));
      expect(result.exitCode, 6);
      expect(result.out, isEmpty);
      expect(result.err, contains('disconnected'));
    });

    test('the ticker is disposed once the wait ends', () async {
      await seated();
      final ticker = FakeTicker();
      floor.ticker = ticker;

      await run(['monitor', '--wait', '--timeout', '0.2']);

      expect(ticker.disposed, isTrue);
    });
  });
}
