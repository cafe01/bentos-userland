import 'dart:typed_data';

import '../bentos.dart';
import 'in_process_driver.dart';

/// The in-process portal — a minimal bentos-kernel living in the consumer's
/// own process, just enough real logic to connect the two ends:
///
/// - a **static cap map**: path prefix → driver (the kernel's
///   `path → driver channel` map, in-process flavor);
/// - an **open-session table**: fd → (driver, fh);
/// - the **vocabulary translation**: userland `close()` fans out to driver
///   `flush` + `release`.
///
/// No dup/refcount/proc fd table — fds are 1:1 with sessions, per the
/// pragmatic line. This is the dev/test door of the architecture
/// (`bentos-kernel-architecture.md` §3); the logic it mimics is exactly what
/// the real kernel's `handle_syscall` + VFS relay perform.
class InProcessBentos implements Bentos {
  /// Cap map: longest-prefix wins is unnecessary — first matching prefix.
  final Map<String, InProcessDriver> _capMap;

  final Map<int, _Session> _sessions = {};
  int _nextFd = 3; // 0/1/2 taken, in spirit.

  InProcessBentos({required Map<String, InProcessDriver> capMap})
    : _capMap = Map.of(capMap);

  @override
  Future<int> open(String path, {OpenMode mode = OpenMode.readWrite}) async {
    final driver = _resolve(path);
    if (driver == null) {
      throw BentosException(BentosErrno.enoent, 'open', path);
    }
    final fh = await driver.open(path);
    final fd = _nextFd++;
    _sessions[fd] = _Session(driver, fh);
    return fd;
  }

  @override
  Future<Uint8List> read(int fd) {
    final s = _session(fd, 'read');
    return s.driver.read(s.fh);
  }

  @override
  Future<void> write(int fd, Uint8List data) {
    final s = _session(fd, 'write');
    return s.driver.write(s.fh, data);
  }

  @override
  Future<Uint8List> ioctl(int fd, int cmd, Uint8List data) {
    final s = _session(fd, 'ioctl');
    return s.driver.ioctl(s.fh, cmd, data);
  }

  @override
  Future<bool> poll(int fd) {
    final s = _session(fd, 'poll');
    return s.driver.poll(s.fh);
  }

  @override
  Future<void> fsync(int fd) {
    final s = _session(fd, 'fsync');
    return s.driver.fsync(s.fh);
  }

  @override
  Future<void> close(int fd) async {
    final s = _session(fd, 'close');
    // Userland close() arrives at the driver as flush + release.
    await s.driver.flush(s.fh);
    await s.driver.release(s.fh);
    _sessions.remove(fd);
  }

  InProcessDriver? _resolve(String path) {
    for (final entry in _capMap.entries) {
      if (path.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  _Session _session(int fd, String operation) {
    final s = _sessions[fd];
    if (s == null) {
      throw BentosException(BentosErrno.ebadf, operation, 'fd $fd');
    }
    return s;
  }
}

class _Session {
  final InProcessDriver driver;
  final int fh;
  _Session(this.driver, this.fh);
}
