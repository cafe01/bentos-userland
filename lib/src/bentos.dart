import 'dart:typed_data';

/// How a capability session is opened.
enum OpenMode { readOnly, writeOnly, readWrite }

/// POSIX-style error codes surfaced by the syscall surface.
enum BentosErrno {
  /// No capability at this path.
  enoent,

  /// The fd does not name an open session.
  ebadf,

  /// Permission denied — e.g. the driver behind the device lacks a credential.
  eacces,

  /// Operation not supported by the device / invalid for this session state.
  enotsup,

  /// Invalid argument (bad ioctl payload, bad flags, ...).
  einval,

  /// Device-side failure.
  eio,
}

/// A syscall failed. Carries the errno and the failing operation.
class BentosException implements Exception {
  final BentosErrno errno;
  final String operation;
  final String? detail;

  const BentosException(this.errno, this.operation, [this.detail]);

  @override
  String toString() =>
      'BentosException(${errno.name}) in $operation${detail == null ? '' : ': $detail'}';
}

/// The bentos syscall surface — the client-side contract over bentos-kernel
/// capabilities, portal-agnostic.
///
/// This is the stdlib's core layer (`core/vfs.h`): the only layer that knows
/// portals exist. Implementations are portals — in-process (dev/test), gRPC,
/// real POSIX `/dev` nodes — and a program written against this interface
/// never knows which one it walked through.
///
/// Two laws, inherited from the architecture (`bentos-kernel-architecture.md` §2):
///
/// - **The fd is the session.** [open] allocates it; all per-consumer state
///   hangs off it; [close] ends it. fds are 1:1 with sessions (no dup).
/// - **The surface is transport-agnostic.** No operation's semantics may
///   depend on which portal delivered it.
///
/// Payloads are opaque bytes at this layer. Subsystem-typed layers (e.g. the
/// chat-inference `ChatDevice`) sit on top and own the frame encodings.
abstract interface class Bentos {
  /// Allocates a session against the capability named by [path]
  /// (e.g. `/dev/llm/anthropic/claude-sonnet-4`).
  ///
  /// Returns the fd that IS the session.
  ///
  /// Throws [BentosException] `enoent` if no capability lives at [path].
  Future<int> open(String path, {OpenMode mode = OpenMode.readWrite});

  /// Pulls the next output frame from the session.
  ///
  /// Blocks (asynchronously) until a frame is available. An empty result is
  /// end-of-stream, mirroring `read(2)` returning 0.
  Future<Uint8List> read(int fd);

  /// Pushes one input frame into the session. One call, one frame.
  Future<void> write(int fd, Uint8List data);

  /// Configures the session / queries device state.
  ///
  /// [cmd] identifiers and payload encodings are subsystem territory
  /// (e.g. `CHAT_SET_FIRST_ROLE` for `/dev/llm/*`).
  Future<Uint8List> ioctl(int fd, int cmd, Uint8List data);

  /// Readiness — is there a frame to [read] right now?
  Future<bool> poll(int fd);

  /// Consumer-side barrier (e.g. trigger processing before the first read).
  Future<void> fsync(int fd);

  /// Ends the session. The fd is invalid afterwards.
  Future<void> close(int fd);
}
