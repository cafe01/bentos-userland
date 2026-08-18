/// `presence` — an instance made visible, as a view: a detached worktree at a
/// point, never a checked-out line, so the same instance may stand at several
/// directories at once (place R18).
library;

import 'dart:io';

import 'instance.dart';
import 'spine.dart';

/// The slice of `Copy` this component owns.
abstract interface class CopyPresence {
  /// Stand [instance] as files at [at], a directory the caller chose.
  ///
  /// A view at [point], or at the instance's current position when none is
  /// given. Never a checked-out line.
  Future<Materialization> materialize(
    Instance instance, {
    required Directory at,
    Point? point,
  });

  /// Take a materialization down. Destroys nothing: what was landed is in the
  /// history, and what was never landed was never the instance's.
  Future<void> release(Directory at);

  /// Every materialization this copy holds, by instance. The truth a place
  /// reads presence from (place R13 — it caches none of this).
  Map<String, Set<Directory>> get materializations;
}

final class Materialization {
  const Materialization({
    required this.instance,
    required this.directory,
    required this.point,
    required this.pinned,
  });

  final String instance;
  final Directory directory;

  /// The point these files stand at.
  final Point point;

  /// True when the caller asked for a fixed point, in which case a landing
  /// never moves it.
  final bool pinned;
}
