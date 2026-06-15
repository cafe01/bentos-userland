import 'dart:typed_data';

import 'package:bentos_abi/bentos_abi.dart';
import 'package:fixnum/fixnum.dart' as fixnum;

import '../bentos.dart';

/// The portal-backed libc — the same [Bentos] contract delivered over any
/// [Portal] (isolate channel, UDS socket, real POSIX fd).
///
/// [open] sends the path across the wire; the kernel assigns the fd and echoes
/// it back in [OpenResp]. Every subsequent op carries that fd; the kernel owns
/// the session table. [PortalBentos] holds no session state.
class PortalBentos implements Bentos {
  static const _readSize = 1 << 16;

  final Portal _portal;

  PortalBentos(this._portal);

  @override
  Future<int> open(String path, {OpenMode mode = OpenMode.readWrite}) async {
    final resp = await _portal.syscall(
      SyscallRequest(open: OpenReq(path: path, flags: _openFlags(mode))),
    );
    _check(resp, 'open', path);
    return resp.open.fd.toInt();
  }

  @override
  Future<Uint8List> read(int fd) async {
    final resp = await _portal.syscall(
      SyscallRequest(
        read: ReadReq(fd: fixnum.Int64(fd), size: fixnum.Int64(_readSize)),
      ),
    );
    _check(resp, 'read', 'fd $fd');
    return Uint8List.fromList(resp.read.data);
  }

  @override
  Future<void> write(int fd, Uint8List data) async {
    final resp = await _portal.syscall(
      SyscallRequest(write: WriteReq(fd: fixnum.Int64(fd), data: data)),
    );
    _check(resp, 'write', 'fd $fd');
  }

  @override
  Future<Uint8List> ioctl(int fd, int cmd, Uint8List data) async {
    final resp = await _portal.syscall(
      SyscallRequest(
        ioctl: IoctlReq(
          fd: fixnum.Int64(fd),
          cmd: cmd,
          inBuf: data,
          outBufsz: fixnum.Int64(_readSize),
        ),
      ),
    );
    _check(resp, 'ioctl', 'fd $fd');
    return Uint8List.fromList(resp.ioctl.buf);
  }

  @override
  Future<bool> poll(int fd) async {
    final resp = await _portal.syscall(
      SyscallRequest(poll: PollReq(fd: fixnum.Int64(fd))),
    );
    _check(resp, 'poll', 'fd $fd');
    return resp.poll.ready;
  }

  @override
  Future<void> fsync(int fd) async {
    final resp = await _portal.syscall(
      SyscallRequest(fsync: FsyncReq(fd: fixnum.Int64(fd))),
    );
    _check(resp, 'fsync', 'fd $fd');
  }

  @override
  Future<void> close(int fd) async {
    final resp = await _portal.syscall(
      SyscallRequest(close: CloseReq(fd: fixnum.Int64(fd))),
    );
    _check(resp, 'close', 'fd $fd');
  }

  static int _openFlags(OpenMode mode) => switch (mode) {
        OpenMode.readOnly => 0,
        OpenMode.writeOnly => 1,
        OpenMode.readWrite => 2,
      };

  void _check(SyscallResponse resp, String operation, [String? detail]) {
    if (resp.errno == 0) return;
    final errno = switch (resp.errno) {
      2 => BentosErrno.enoent,
      9 => BentosErrno.ebadf,
      13 => BentosErrno.eacces,
      22 => BentosErrno.einval,
      38 => BentosErrno.enotsup,
      _ => BentosErrno.eio,
    };
    throw BentosException(errno, operation, detail);
  }
}
