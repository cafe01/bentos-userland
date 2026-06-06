import 'dart:typed_data';

import 'package:bentos_userland/bentos_userland.dart';
import 'package:test/test.dart';

/// A driver that records every op it receives — enough device to exercise
/// the surface, no domain logic.
class RecordingDriver implements InProcessDriver {
  final List<String> ops = [];
  final Map<int, List<Uint8List>> written = {};
  int _nextFh = 1;

  @override
  Future<int> open(String path) async {
    final fh = _nextFh++;
    ops.add('open($path) -> fh $fh');
    written[fh] = [];
    return fh;
  }

  @override
  Future<Uint8List> read(int fh) async {
    ops.add('read($fh)');
    // Echo device: replay the last written frame, then EOF.
    final pending = written[fh]!;
    return pending.isEmpty ? Uint8List(0) : pending.removeAt(0);
  }

  @override
  Future<void> write(int fh, Uint8List data) async {
    ops.add('write($fh, ${data.length}b)');
    written[fh]!.add(data);
  }

  @override
  Future<Uint8List> ioctl(int fh, int cmd, Uint8List data) async {
    ops.add('ioctl($fh, $cmd)');
    return Uint8List(0);
  }

  @override
  Future<bool> poll(int fh) async {
    ops.add('poll($fh)');
    return written[fh]!.isNotEmpty;
  }

  @override
  Future<void> fsync(int fh) async => ops.add('fsync($fh)');

  @override
  Future<void> flush(int fh) async => ops.add('flush($fh)');

  @override
  Future<void> release(int fh) async {
    ops.add('release($fh)');
    written.remove(fh);
  }
}

void main() {
  late RecordingDriver driver;
  late Bentos bentos;

  setUp(() {
    driver = RecordingDriver();
    bentos = InProcessBentos(capMap: {'/dev/llm/': driver});
  });

  group('open', () {
    test('allocates a session and returns the fd that names it', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      expect(fd, greaterThanOrEqualTo(3));
      expect(driver.ops, ['open(/dev/llm/anthropic/claude-sonnet-4) -> fh 1']);
    });

    test('two opens are two independent sessions', () async {
      final a = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      final b = await bentos.open('/dev/llm/anthropic/claude-haiku-4-5');
      expect(a, isNot(b));
    });

    test('unknown path throws ENOENT', () {
      expect(
        () => bentos.open('/dev/tts/voice'),
        throwsA(
          isA<BentosException>().having(
            (e) => e.errno,
            'errno',
            BentosErrno.enoent,
          ),
        ),
      );
    });
  });

  group('write / read / poll', () {
    test('write pushes one frame; read pulls it back; empty read is EOF',
        () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      final frame = Uint8List.fromList([1, 2, 3]);

      await bentos.write(fd, frame);
      expect(await bentos.poll(fd), isTrue);

      expect(await bentos.read(fd), frame);
      expect(await bentos.poll(fd), isFalse);
      expect(await bentos.read(fd), isEmpty); // EOF mirrors read(2) -> 0
    });
  });

  group('close', () {
    test('arrives at the driver as flush + release', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      await bentos.close(fd);
      expect(driver.ops.sublist(1), ['flush(1)', 'release(1)']);
    });

    test('the fd is invalid afterwards — EBADF', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      await bentos.close(fd);
      expect(
        () => bentos.read(fd),
        throwsA(
          isA<BentosException>().having(
            (e) => e.errno,
            'errno',
            BentosErrno.ebadf,
          ),
        ),
      );
    });
  });

  group('ioctl / fsync', () {
    test('relay to the driver session', () async {
      final fd = await bentos.open('/dev/llm/anthropic/claude-sonnet-4');
      await bentos.ioctl(fd, 42, Uint8List(0));
      await bentos.fsync(fd);
      expect(driver.ops.sublist(1), ['ioctl(1, 42)', 'fsync(1)']);
    });
  });
}
