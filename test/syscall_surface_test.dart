/// The in-process portal exercised against REAL Driver SDK drivers — no fakes,
/// no parallel driver contract. echo is the SDK's P1 (`StreamDriver`), kv is
/// its P2 (`WriteReadDriver`), each served over the kernel-side end of a
/// connected channel pair (`driver.serveChannel(pair.foreign)`).
///
/// The kernel-job assertions the pattern frameworks deliberately hide — the
/// `close()` → `flush` + `release` vocabulary translation and the ioctl/fsync
/// relay — are asserted against a raw recording [BentosDriver] (real SDK L1,
/// the same instrument the SDK's own driver_test uses), the only driver that
/// surfaces those ops.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:bentos_userland/bentos_userland.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// echo — the SDK's P1 example driver (`/dev/echo`): write bytes, read back.
StreamDriver<StreamController<Uint8List>> echoDriver() =>
    StreamDriver<StreamController<Uint8List>>(StreamOps(
      onSessionStart: (flags) => StreamController<Uint8List>(),
      onData: (data, {required session}) {
        session!.add(Uint8List.fromList(data));
        return data.length;
      },
      outputStream: ({required session}) => session!.stream,
      onSessionEnd: ({required session}) => session!.close(),
    ));

/// kv — the SDK's P2 example driver (`/dev/kv`): "key=value" stores, "key" queries.
WriteReadDriver<Object> kvDriver(Map<String, String> store) =>
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

/// Connect a driver to a fresh in-process channel pair, returning the
/// kernel-side end. [serveChannel] is invoked synchronously by the caller.
StreamChannel<Uint8List> _connect(void Function(StreamChannel<Uint8List>) serve) {
  final pair = StreamChannelController<Uint8List>();
  serve(pair.foreign);
  return pair.local;
}

void main() {
  group('against echo (P1 StreamDriver)', () {
    late Bentos bentos;

    setUp(() {
      final echo = echoDriver();
      bentos = InProcessBentos(
        capMap: {'/dev/echo': _connect(echo.serveChannel)},
      );
    });

    test('open allocates a session and returns the fd that names it', () async {
      final fd = await bentos.open('/dev/echo');
      expect(fd, greaterThanOrEqualTo(3));
    });

    test('two opens are two independent sessions', () async {
      final a = await bentos.open('/dev/echo');
      final b = await bentos.open('/dev/echo');
      expect(a, isNot(b));

      // A frame written to one session never surfaces on the other.
      await bentos.write(a, Uint8List.fromList([1, 2, 3]));
      expect(await bentos.poll(b), isFalse);
      expect(await bentos.read(b), isEmpty);
      expect(await bentos.read(a), equals([1, 2, 3]));
    });

    test('write pushes one frame; read pulls it back; empty read is EOF',
        () async {
      final fd = await bentos.open('/dev/echo');
      final frame = Uint8List.fromList([1, 2, 3]);

      await bentos.write(fd, frame);
      expect(await bentos.poll(fd), isTrue);

      expect(await bentos.read(fd), equals(frame));
      expect(await bentos.poll(fd), isFalse);
      expect(await bentos.read(fd), isEmpty); // EOF mirrors read(2) -> 0
    });

    test('unknown path throws ENOENT', () {
      expect(
        () => bentos.open('/dev/tts/voice'),
        throwsA(isA<BentosException>()
            .having((e) => e.errno, 'errno', BentosErrno.enoent)),
      );
    });

    test('the fd is invalid after close — EBADF', () async {
      final fd = await bentos.open('/dev/echo');
      await bentos.close(fd);
      expect(
        () => bentos.read(fd),
        throwsA(isA<BentosException>()
            .having((e) => e.errno, 'errno', BentosErrno.ebadf)),
      );
    });
  });

  group('against kv (P2 WriteReadDriver)', () {
    late Bentos bentos;

    setUp(() {
      final kv = kvDriver(<String, String>{});
      bentos = InProcessBentos(
        capMap: {'/dev/kv': _connect(kv.serveChannel)},
      );
    });

    test('write-then-read: store with fsync barrier, then query', () async {
      final fd = await bentos.open('/dev/kv');

      // Store: write the request, fsync as the consumer-side barrier, read OK.
      await bentos.write(fd, Uint8List.fromList(utf8.encode('name=bentos')));
      await bentos.fsync(fd);
      expect(utf8.decode(await bentos.read(fd)), equals('OK\n'));

      // Query: write the key, read triggers submission, get the value back.
      await bentos.write(fd, Uint8List.fromList(utf8.encode('name')));
      expect(utf8.decode(await bentos.read(fd)), equals('bentos\n'));

      await bentos.close(fd);
    });
  });

  group('kernel-job assertions (raw recording BentosDriver, L1)', () {
    late List<String> ops;
    late Bentos bentos;

    setUp(() {
      ops = [];
      final recorder = BentosDriver(
        onOpen: (req, ctx) {
          ops.add('open(fh ${ctx.fh})');
          return FuseResponse(open: OpenReply());
        },
        onIoctl: (req, ctx) {
          ops.add('ioctl(fh ${ctx.fh}, cmd ${req.cmd})');
          return FuseResponse(ioctl: IoctlReply(result: 0, buf: const []));
        },
        onFsync: (req, ctx) {
          ops.add('fsync(fh ${ctx.fh})');
          return FuseResponse();
        },
        onFlush: (req, ctx) {
          ops.add('flush(fh ${ctx.fh})');
          return FuseResponse();
        },
        onRelease: (req, ctx) {
          ops.add('release(fh ${ctx.fh})');
          return FuseResponse();
        },
      );
      bentos = InProcessBentos(
        capMap: {'/dev/llm/': _connect(recorder.serveChannel)},
      );
    });

    test('close() arrives at the driver as flush + release', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      await bentos.close(fd);
      expect(ops, equals(['open(fh 1)', 'flush(fh 1)', 'release(fh 1)']));
    });

    test('ioctl and fsync relay to the driver session under its fh', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      await bentos.ioctl(fd, 42, Uint8List(0));
      await bentos.fsync(fd);
      expect(ops.sublist(1), equals(['ioctl(fh 1, cmd 42)', 'fsync(fh 1)']));
    });

    test('a driver errno surfaces as a BentosException', () async {
      final driver = BentosDriver(
        onOpen: (req, ctx) => FuseResponse(open: OpenReply()),
        onRead: (req, ctx) => throw DriverError.notFound('missing'),
      );
      final b = InProcessBentos(
        capMap: {'/dev/x': _connect(driver.serveChannel)},
      );
      final fd = await b.open('/dev/x');
      expect(
        () => b.read(fd),
        throwsA(isA<BentosException>()
            .having((e) => e.errno, 'errno', BentosErrno.enoent)),
      );
    });
  });
}
