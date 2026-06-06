import 'dart:typed_data';

/// The driver side of the in-process portal — the kernel-mimic's stand-in for
/// the real driver channel (Driver SDK, `FuseMessage` wire).
///
/// This speaks the **driver vocabulary** (libfuse-shaped), not the userland
/// surface: note `flush` + `release` where userland has one `close()`. The
/// kernel owns that translation, on every portal.
///
/// `fh` is the driver-side session handle, allocated by [open]. The kernel
/// maps consumer fds to (driver, fh) pairs; a driver only ever sees its own
/// handles.
abstract interface class InProcessDriver {
  /// Allocates a driver-side session for the capability at [path].
  /// Returns the file handle `fh` naming it.
  Future<int> open(String path);

  /// Next output frame for session [fh]. Empty = end-of-stream.
  Future<Uint8List> read(int fh);

  /// One input frame into session [fh].
  Future<void> write(int fh, Uint8List data);

  /// Device configuration / state query on session [fh].
  Future<Uint8List> ioctl(int fh, int cmd, Uint8List data);

  /// Is there a frame to read on session [fh]?
  Future<bool> poll(int fh);

  /// Consumer-side barrier on session [fh].
  Future<void> fsync(int fh);

  /// First half of a userland `close()`.
  Future<void> flush(int fh);

  /// Second half of a userland `close()` — the session dies here.
  Future<void> release(int fh);
}
