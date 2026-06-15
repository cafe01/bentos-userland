/// Parity gate: PortalBentos (over IsolatePortal + kernelIsolateMain) produces
/// outputs identical to InProcessBentos (over the same driver logic inline) for
/// every op — including the typed error on every error path.
///
/// What "identical" means here: same [BentosErrno] + same operation string on
/// exceptions; same bytes / bool on success. The [BentosException.detail] is
/// intentionally NOT compared — it is human-readable prose, not a contract.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bentos_abi/bentos_abi.dart' show IsolatePortal;
import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_kernel/bentos_kernel.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers — mirror the private helpers in bentos-kernel's isolate_server.dart.
// ---------------------------------------------------------------------------

StreamChannel<Uint8List> _connect(
    void Function(StreamChannel<Uint8List>) serve) {
  final pair = StreamChannelController<Uint8List>();
  serve(pair.foreign);
  return pair.local;
}

InProcessBentos _inProcess(List<String> devices) {
  final capMap = <String, StreamChannel<Uint8List>>{};
  for (final device in devices) {
    switch (device) {
      case '/dev/echo':
        capMap[device] = _connect(_echoDriver().serveChannel);
      case '/dev/kv':
        capMap[device] = _connect(_kvDriver({}).serveChannel);
    }
  }
  return InProcessBentos(capMap: capMap);
}

StreamDriver<StreamController<Uint8List>> _echoDriver() =>
    StreamDriver<StreamController<Uint8List>>(StreamOps(
      onSessionStart: (flags) => StreamController<Uint8List>(),
      onData: (data, {required session}) {
        session!.add(Uint8List.fromList(data));
        return data.length;
      },
      outputStream: ({required session}) => session!.stream,
      onSessionEnd: ({required session}) => session!.close(),
    ));

WriteReadDriver<Object> _kvDriver(Map<String, String> store) =>
    WriteReadDriver<Object>(WriteReadOps(
      onSessionStart: (flags) => Object(),
      onRequest: (input, {required session}) async {
        final text = utf8.decode(input).trim();
        if (text.contains('=')) {
          final parts = text.split('=');
          store[parts[0]] = parts.sublist(1).join('=');
          return Uint8List.fromList(utf8.encode('OK\n'));
        }
        return Uint8List.fromList(
            utf8.encode('${store[text] ?? "(not found)"}\n'));
      },
    ));

// ---------------------------------------------------------------------------
// Matchers
// ---------------------------------------------------------------------------

Matcher _bentosError(BentosErrno errno, String operation) =>
    isA<BentosException>()
        .having((e) => e.errno, 'errno', errno)
        .having((e) => e.operation, 'operation', operation);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PortalBentos parity — echo (/dev/echo)', () {
    late Bentos inProc;
    late Bentos portal;
    late IsolatePortal isoPortal;

    setUp(() async {
      inProc = _inProcess(['/dev/echo']);
      final (p, _) = await spawnKernelIsolate(['/dev/echo']);
      isoPortal = p;
      portal = PortalBentos(isoPortal);
    });

    tearDown(() => isoPortal.close());

    test('open returns a valid fd (≥ 3) on both', () async {
      final fdI = await inProc.open('/dev/echo');
      final fdP = await portal.open('/dev/echo');
      expect(fdI, greaterThanOrEqualTo(3));
      expect(fdP, greaterThanOrEqualTo(3));
    });

    test('write then read round-trips the same bytes', () async {
      final frame = Uint8List.fromList([10, 20, 30, 40]);

      final fdI = await inProc.open('/dev/echo');
      await inProc.write(fdI, frame);
      final gotI = await inProc.read(fdI);

      final fdP = await portal.open('/dev/echo');
      await portal.write(fdP, frame);
      final gotP = await portal.read(fdP);

      expect(gotI, equals(frame));
      expect(gotP, equals(frame));
    });

    test('poll is false before write, true after', () async {
      final fdI = await inProc.open('/dev/echo');
      final fdP = await portal.open('/dev/echo');

      expect(await inProc.poll(fdI), isFalse);
      expect(await portal.poll(fdP), isFalse);

      await inProc.write(fdI, Uint8List.fromList([1]));
      await portal.write(fdP, Uint8List.fromList([1]));

      expect(await inProc.poll(fdI), isTrue);
      expect(await portal.poll(fdP), isTrue);
    });

    test('read after EOF returns empty on both', () async {
      final frame = Uint8List.fromList([7, 8]);

      final fdI = await inProc.open('/dev/echo');
      await inProc.write(fdI, frame);
      await inProc.read(fdI); // consume
      final eofI = await inProc.read(fdI);

      final fdP = await portal.open('/dev/echo');
      await portal.write(fdP, frame);
      await portal.read(fdP);
      final eofP = await portal.read(fdP);

      expect(eofI, isEmpty);
      expect(eofP, isEmpty);
    });

    test('open unknown path → ENOENT on both', () {
      expect(
        () => inProc.open('/dev/nosuchpath'),
        throwsA(_bentosError(BentosErrno.enoent, 'open')),
      );
      expect(
        () => portal.open('/dev/nosuchpath'),
        throwsA(_bentosError(BentosErrno.enoent, 'open')),
      );
    });

    test('read/write/poll/fsync/close on bad fd → EBADF on both', () async {
      const badFd = 999;

      for (final op in ['read', 'write', 'poll', 'fsync', 'close']) {
        Future<void> run(Bentos b) => switch (op) {
              'read' => b.read(badFd).then((_) {}),
              'write' => b.write(badFd, Uint8List(0)),
              'poll' => b.poll(badFd).then((_) {}),
              'fsync' => b.fsync(badFd),
              'close' => b.close(badFd),
              _ => throw StateError(op),
            };

        expect(
          () => run(inProc),
          throwsA(_bentosError(BentosErrno.ebadf, op)),
          reason: 'inProc $op(999)',
        );
        expect(
          () => run(portal),
          throwsA(_bentosError(BentosErrno.ebadf, op)),
          reason: 'portal $op(999)',
        );
      }
    });

    test('fd is invalid after close — EBADF on both', () async {
      final fdI = await inProc.open('/dev/echo');
      await inProc.close(fdI);

      final fdP = await portal.open('/dev/echo');
      await portal.close(fdP);

      expect(
        () => inProc.read(fdI),
        throwsA(_bentosError(BentosErrno.ebadf, 'read')),
      );
      expect(
        () => portal.read(fdP),
        throwsA(_bentosError(BentosErrno.ebadf, 'read')),
      );
    });
  });

  group('PortalBentos parity — kv (/dev/kv)', () {
    late Bentos inProc;
    late Bentos portal;
    late IsolatePortal isoPortal;

    setUp(() async {
      inProc = _inProcess(['/dev/kv']);
      final (p, _) = await spawnKernelIsolate(['/dev/kv']);
      isoPortal = p;
      portal = PortalBentos(isoPortal);
    });

    tearDown(() => isoPortal.close());

    test('write-fsync-read store, write-read query: same bytes', () async {
      final key = utf8.encode('city');
      final kv = utf8.encode('city=rome');

      Future<Uint8List> runStore(Bentos b) async {
        final fd = await b.open('/dev/kv');
        await b.write(fd, Uint8List.fromList(kv));
        await b.fsync(fd);
        await b.read(fd); // "OK\n" — consumed, not asserted (same on both impls)
        await b.write(fd, Uint8List.fromList(key));
        final val = await b.read(fd);
        await b.close(fd);
        return val;
      }

      final resI = await runStore(inProc);
      final resP = await runStore(portal);

      expect(utf8.decode(resI), equals('rome\n'));
      expect(utf8.decode(resP), equals('rome\n'));
      expect(resI, equals(resP));
    });

    test('ioctl with bad fd → EBADF on both', () {
      expect(
        () => inProc.ioctl(999, 0, Uint8List(0)),
        throwsA(_bentosError(BentosErrno.ebadf, 'ioctl')),
      );
      expect(
        () => portal.ioctl(999, 0, Uint8List(0)),
        throwsA(_bentosError(BentosErrno.ebadf, 'ioctl')),
      );
    });
  });
}
