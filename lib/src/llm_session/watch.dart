/// The session's clock: the ref moving, told to whoever is looking at it.
///
/// A face reads an entity by folding the tree at a ref, so it is stale the
/// instant another body commits — and every body here is another body: the
/// runner the session is armed with, the shell, a second window. What makes the
/// face current again is watching the one thing that carries state, which is
/// the ref itself. The live seam ([LiveWatch]) is a different faculty: it
/// animates a turn in flight, is best-effort by design, and a reply that lands
/// with nobody listening still moved the ref.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity/git_entity.dart';
import 'session.dart';

/// A watch on one ref of one entity, reporting each new tip.
///
/// Git has no notification of its own, so the movement is observed twice over:
/// the filesystem where the ref is written — the loose file under
/// `refs/heads/`, and `packed-refs` for a ref that has been packed away — and a
/// slow poll beneath it, because a filesystem watch is a courtesy of the
/// platform and not a guarantee. Both paths end in the same question, `what is
/// the tip now`, and the answer is deduplicated by sha: a watch that fires ten
/// times for one commit emits once, and one that never fires at all is only as
/// late as [poll].
final class SessionWatch {
  SessionWatch._(this._entity, this.ref, this._seen);

  final GitEntity _entity;

  /// The ref being watched — a session's main line, or one of its forks.
  final String ref;

  final _controller = StreamController<String>.broadcast();
  final _subscriptions = <StreamSubscription<FileSystemEvent>>[];
  Timer? _timer;
  String? _seen;
  bool _checking = false;
  bool _pending = false;
  bool _closed = false;

  /// Every tip this ref takes from now on. The tip at the moment of opening is
  /// not emitted: the caller has just read it, and what it wants told is what
  /// happens next.
  Stream<String> get tips => _controller.stream;

  /// The tip last seen — what the watcher's reader is, or is about to be,
  /// folded at.
  String? get tip => _seen;

  static Future<SessionWatch> open(
    GitEntity entity, {
    String ref = mainRef,
    Duration poll = const Duration(seconds: 2),
  }) async {
    final watch = SessionWatch._(entity, ref, await entity.head(ref));
    watch._listen(Directory(p.join(entity.gitDir.path, 'refs', 'heads')));
    watch._listen(entity.gitDir); // packed-refs, and a ref hierarchy created late
    watch._timer = Timer.periodic(poll, (_) => watch._check());
    return watch;
  }

  /// Ask now, rather than waiting for the poll — what a caller does when it has
  /// just written and wants its own transaction reflected without a delay.
  Future<void> refresh() => _check();

  void _listen(Directory dir) {
    if (!dir.existsSync()) return;
    _subscriptions.add(
      dir.watch(recursive: false).listen(
            (_) => _check(),
            // The entity was moved or removed under us; the poll keeps the
            // watch alive and honest, and a dead ref simply never moves again.
            onError: (Object _) {},
            cancelOnError: false,
          ),
    );
  }

  /// One question at a time, and never a lost one: an event arriving mid-check
  /// re-asks once the answer is in, so the last state of the ref is always the
  /// one reported.
  Future<void> _check() async {
    if (_closed) return;
    if (_checking) {
      _pending = true;
      return;
    }
    _checking = true;
    try {
      do {
        _pending = false;
        final head = await _entity.head(ref);
        if (_closed) return;
        if (head != null && head != _seen) {
          _seen = head;
          _controller.add(head);
        }
      } while (_pending);
    } finally {
      _checking = false;
    }
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _controller.close();
  }
}
