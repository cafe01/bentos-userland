import 'dart:async';
import 'dart:typed_data';

import 'package:bentos_driver_sdk/bentos_driver_sdk.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:stream_channel/stream_channel.dart';

import '../bentos.dart';

/// The in-process portal — a minimal bentos-kernel living in the consumer's
/// own process, just enough real logic to connect the two ends.
///
/// This is the dev/test door of the architecture
/// (`bentos-kernel-architecture.md` §3): no wire, no transport. But it is NOT
/// a fake — it is the real kernel role. The kernel is always the **channel
/// client**; drivers are always **channel servers** (§4). Here that channel is
/// the kernel-side end of a connected [StreamChannel] pair whose other end a
/// real [BentosDriver] serves (`driver.serveChannel(...)`), §6: a driver is
/// just the P in IPC, behind one channel contract — an out-of-process socket
/// or an in-process Isolate are the same driver.
///
/// What this portal performs is exactly the real kernel's `handle_syscall` +
/// VFS relay:
///
/// - a **static cap map**: path prefix → driver channel;
/// - an **open-session table**: fd → (driver channel, fh);
/// - **correlation by id**: each request carries a unique id the driver echoes;
/// - the **vocabulary translation**: a userland `close()` fans out to driver
///   `flush` + `release` (§2 warning — the two vocabularies are near-1:1 in
///   names, not in semantics).
///
/// Payloads are opaque [FuseMessage] frames; the portal never learns what a
/// ChatMessage is. No dup/refcount/proc fd table — fds are 1:1 with sessions,
/// per the pragmatic line.
class InProcessBentos implements Bentos {
  /// Default read frame size requested from the driver — the chardev returns
  /// whatever is available, never more than this.
  static const _readSize = 1 << 16;

  // POSIX poll event bits.
  static const _pollin = 0x01;

  final Map<String, _DriverChannel> _capMap;
  final Map<int, _Session> _sessions = {};

  int _nextFh = 1;
  int _nextFd = 3; // 0/1/2 taken, in spirit.

  /// Builds the portal over a cap map of path prefix → kernel-side channel to a
  /// serving [BentosDriver]. A channel shared by several prefixes is
  /// demultiplexed once (one connection, many fh-keyed sessions).
  InProcessBentos({required Map<String, StreamChannel<Uint8List>> capMap})
      : _capMap = _wrap(capMap);

  static Map<String, _DriverChannel> _wrap(
    Map<String, StreamChannel<Uint8List>> capMap,
  ) {
    final wrappers = <StreamChannel<Uint8List>, _DriverChannel>{};
    return capMap.map(
      (prefix, channel) => MapEntry(
        prefix,
        wrappers.putIfAbsent(channel, () => _DriverChannel(channel)),
      ),
    );
  }

  @override
  Future<int> open(String path, {OpenMode mode = OpenMode.readWrite}) async {
    final channel = _resolve(path);
    if (channel == null) {
      throw BentosException(BentosErrno.enoent, 'open', path);
    }
    final fh = _nextFh++;
    final resp = await channel.request(
      fh,
      FuseRequest(open: OpenReq(flags: _openFlags(mode))),
    );
    _check(resp, 'open', path);
    final fd = _nextFd++;
    _sessions[fd] = _Session(channel, fh);
    return fd;
  }

  @override
  Future<Uint8List> read(int fd) async {
    final s = _session(fd, 'read');
    final resp = await s.channel.request(
      s.fh,
      FuseRequest(
        read: ReadReq(
          size: fixnum.Int64(_readSize),
          offset: fixnum.Int64(0),
        ),
      ),
    );
    _check(resp, 'read');
    return Uint8List.fromList(resp.buf.data);
  }

  @override
  Future<void> write(int fd, Uint8List data) async {
    final s = _session(fd, 'write');
    final resp = await s.channel.request(
      s.fh,
      FuseRequest(write: WriteReq(data: data, offset: fixnum.Int64(0))),
    );
    _check(resp, 'write');
  }

  @override
  Future<Uint8List> ioctl(int fd, int cmd, Uint8List data) async {
    final s = _session(fd, 'ioctl');
    final resp = await s.channel.request(
      s.fh,
      FuseRequest(
        ioctl: IoctlReq(
          cmd: cmd,
          inBuf: data,
          outBufsz: fixnum.Int64(_readSize),
        ),
      ),
    );
    _check(resp, 'ioctl');
    return Uint8List.fromList(resp.ioctl.buf);
  }

  @override
  Future<bool> poll(int fd) async {
    final s = _session(fd, 'poll');
    final resp = await s.channel.request(
      s.fh,
      FuseRequest(poll: PollReq(events: _pollin)),
    );
    _check(resp, 'poll');
    return (resp.poll.revents & _pollin) != 0;
  }

  @override
  Future<void> fsync(int fd) async {
    final s = _session(fd, 'fsync');
    final resp = await s.channel.request(
      s.fh,
      FuseRequest(fsync: FsyncReq(datasync: false)),
    );
    _check(resp, 'fsync');
  }

  @override
  Future<void> close(int fd) async {
    final s = _session(fd, 'close');
    // Userland close() arrives at the driver as flush + release (§2 warning).
    _check(await s.channel.request(s.fh, FuseRequest(flush: FlushReq())),
        'close');
    _check(await s.channel.request(s.fh, FuseRequest(release: ReleaseReq())),
        'close');
    _sessions.remove(fd);
  }

  _DriverChannel? _resolve(String path) {
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

  static int _openFlags(OpenMode mode) => switch (mode) {
        OpenMode.readOnly => 0, // O_RDONLY
        OpenMode.writeOnly => 1, // O_WRONLY
        OpenMode.readWrite => 2, // O_RDWR
      };

  /// Translate a driver-side POSIX errno into the surface's [BentosErrno].
  void _check(FuseResponse resp, String operation, [String? detail]) {
    if (resp.err == 0) return;
    final errno = switch (resp.err) {
      2 => BentosErrno.enoent, // ENOENT
      9 => BentosErrno.ebadf, // EBADF
      13 => BentosErrno.eacces, // EACCES — e.g. driver has no credential
      22 => BentosErrno.einval, // EINVAL
      38 => BentosErrno.enotsup, // ENOSYS
      _ => BentosErrno.eio,
    };
    throw BentosException(
      errno,
      operation,
      detail ?? 'driver errno ${resp.err}',
    );
  }
}

/// One driver connection seen from the kernel side: the channel plus the
/// id→completer demultiplexer that correlates responses to requests (§4 — the
/// `id` field on the wire is the correlation key).
class _DriverChannel {
  _DriverChannel(this._channel) {
    _channel.stream.listen(
      _onResponse,
      onError: _failAll,
      onDone: () => _failAll('driver channel closed', StackTrace.current),
    );
  }

  final StreamChannel<Uint8List> _channel;
  final Map<int, Completer<FuseResponse>> _pending = {};
  int _nextId = 1;

  Future<FuseResponse> request(int fh, FuseRequest req) {
    final id = _nextId++;
    final completer = Completer<FuseResponse>();
    _pending[id] = completer;
    final msg = FuseMessage(
      id: fixnum.Int64(id),
      fh: fixnum.Int64(fh),
      request: req,
    );
    _channel.sink.add(Uint8List.fromList(msg.writeToBuffer()));
    return completer.future;
  }

  void _onResponse(Uint8List bytes) {
    final msg = FuseMessage.fromBuffer(bytes);
    _pending.remove(msg.id.toInt())?.complete(msg.response);
  }

  void _failAll(Object error, StackTrace st) {
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error, st);
    }
  }
}

class _Session {
  final _DriverChannel channel;
  final int fh;
  _Session(this.channel, this.fh);
}
