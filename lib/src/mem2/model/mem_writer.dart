import 'dart:io';

import 'package:path/path.dart' as p;

import 'attention.dart';
import 'mem_page.dart';

/// Atomic writes of a single page file. Three paths: a full body write that
/// stamps the organ's dates, an attention-only rewrite, and a gist-only
/// rewrite — the latter two leaving the body bytes and `modified` untouched.
/// The clock is injected so date behaviour is hermetically testable.
///
/// Every path is a read-modify-write, and each `mem` invocation is its own
/// process, so an in-process guard cannot protect it: two writers racing
/// between one's read and its rename lose whichever landed first. Each
/// method therefore holds an OS-level exclusive lock on a sidecar file under
/// `<store-root>/.mem/locks/`, across its own read through its own rename —
/// a sidecar because the rename swaps the page's inode, and a lock held on
/// the old inode means nothing to whoever opens the path next; kept out of
/// the store proper (`<bank>.mem/`, a git repository) rather than beside the
/// page, since a bank must never see these in `git status`.
final class MemWriter {
  MemWriter(this.now);

  final DateTime Function() now;

  /// Create or replace [file] with a body write. `created` is stamped once (on
  /// first write, or carried from the existing file); `modified` is refreshed
  /// on every body write. Returns the landed page.
  MemPage writeBody(
    File file,
    String topic, {
    required MemType type,
    required Attention attention,
    List<String> tags = const [],
    String? gist,
    required String body,
  }) =>
      mutateBody(file, topic,
          type: type, attention: attention, tags: tags, gist: gist, transform: (_) => body);

  /// Create or replace [file] with a body derived from what is there now:
  /// [transform] receives the current body (empty for a page that does not
  /// yet exist) and returns the successor, read and written under the same
  /// lock. This is the primitive [writeBody] is built from, and the one a
  /// caller whose new body depends on the old one actually needs — passing a
  /// pre-computed body to [writeBody] cannot protect a read that already
  /// happened outside any lock. `created` is stamped once, `modified` is
  /// refreshed on every write. Returns the landed page.
  MemPage mutateBody(
    File file,
    String topic, {
    required MemType type,
    required Attention attention,
    List<String> tags = const [],
    String? gist,
    required String Function(String currentBody) transform,
  }) {
    return _withLock(file, () {
      final stamp = now();
      DateTime created = stamp;
      String currentBody = '';
      if (file.existsSync()) {
        final existing = MemPage.parse(topic, file.readAsStringSync());
        created = existing.fields.created ?? stamp;
        currentBody = existing.body;
      }
      final page = MemPage(
        topic: topic,
        fields: FrontmatterFields(
          type: type,
          attention: attention,
          tags: tags,
          created: created,
          modified: stamp,
          gist: gist,
        ),
        body: transform(currentBody),
      );
      _atomicWrite(file, page.serialize());
      return page;
    });
  }

  /// Attention-only rewrite: replace the `attention:` line in place, leaving
  /// every other byte — body and `modified` — identical. Operates on the raw
  /// text so nothing outside the one line can drift. A page whose attention
  /// was never a legible line (assumed on read, `--to` is the one caller that
  /// may still reach it) has no line to replace — falls back to a structural
  /// rewrite that introduces the key, the same way [regist] must for a gist.
  void refocus(File file, String topic, Attention attention) {
    _withLock(file, () {
      final content = file.readAsStringSync();
      final pattern = RegExp(r'^attention:.*$', multiLine: true);
      if (pattern.hasMatch(content)) {
        _atomicWrite(file, content.replaceFirst(pattern, 'attention: ${attention.render()}'));
        return null;
      }
      final page = MemPage.parse(topic, content);
      final rewritten = MemPage(
        topic: topic,
        fields: page.fields.copyWith(attention: attention),
        body: page.body,
      );
      _atomicWrite(file, rewritten.serialize());
      return null;
    });
  }

  /// Gist-only rewrite: the page's `gist` replaced, every other field — body,
  /// `created`, `modified`, tags, extras — carried through as parsed. Returns
  /// the landed page.
  ///
  /// Structural, where [refocus] is textual, because the gist has two shapes a
  /// line replacement cannot reach: it may be **absent** (no line to replace,
  /// and appending textually means re-deriving the schema order here), and a
  /// hand-written page may carry a **multi-line** YAML scalar (`>`, `|`, or a
  /// wrapped quoted string), where replacing the first line leaves the
  /// continuation behind as body-level garbage that no longer parses. The price
  /// is that a hand-edited page comes back normalized to the organ's own
  /// serialization; a page the organ wrote is byte-identical but for the gist.
  MemPage regist(File file, String topic, String gist) {
    return _withLock(file, () {
      final page = MemPage.parse(topic, file.readAsStringSync());
      final rewritten = MemPage(
        topic: topic,
        fields: page.fields.copyWith(gist: gist),
        body: page.body,
      );
      _atomicWrite(file, rewritten.serialize());
      return rewritten;
    });
  }

  /// Hold an exclusive OS lock on [file]'s sidecar for the duration of
  /// [body], which is a synchronous read-modify-write against [file] itself.
  /// `flock` is per-process, so this is the guard two `mem` invocations
  /// racing on one page actually need — an in-process mutex would be
  /// worthless across processes.
  T _withLock<T>(File file, T Function() body) {
    final storeRoot = _storeRoot(file);
    final lockDir = Directory(p.join(storeRoot.path, '.mem', 'locks'));
    lockDir.createSync(recursive: true);
    final gitignore = File(p.join(storeRoot.path, '.mem', '.gitignore'));
    if (!gitignore.existsSync()) gitignore.writeAsStringSync('*\n');

    final relative = p.relative(file.path, from: storeRoot.path).replaceAll(p.separator, '_');
    final raf = File(p.join(lockDir.path, '$relative.lock')).openSync(mode: FileMode.write);
    var locked = false;
    try {
      raf.lockSync(FileLock.blockingExclusive);
      locked = true;
    } on UnsupportedError {
      // Only `package:file`'s MemoryFileSystem raises this — lockSync and
      // unlockSync are both `throw UnimplementedError('TODO')` in
      // memory_random_access_file.dart (file.dart#140), unconditionally, for
      // every call. It is what runInMemoryFs tests run against, and it has
      // no second process to race in the first place. A real POSIX or
      // Windows filesystem never raises UnsupportedError from a lock
      // attempt — a genuine failure there is a FileSystemException, which
      // this catch does not swallow and which still propagates.
    }
    try {
      return body();
    } finally {
      if (locked) raf.unlockSync();
      raf.closeSync();
    }
  }

  /// The store root a page belongs to: the ancestor directory named
  /// `<bank>.mem`, the bank's own git repository. Falls back to the page's
  /// own directory when no such ancestor exists — a synthetic path used only
  /// by unit tests that exercise this writer directly, off the real store
  /// layout `MemStore` always produces.
  Directory _storeRoot(File file) {
    var dir = file.parent;
    while (true) {
      if (p.basename(dir.path).endsWith('.mem')) return dir;
      final parent = dir.parent;
      if (parent.path == dir.path) return file.parent;
      dir = parent;
    }
  }

  /// The temp file's name must be unique per writer, not merely per target
  /// path: two processes writing the same page at once must never share one
  /// temp file, or one can rename the other's half-written bytes into place.
  void _atomicWrite(File file, String content) {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.$pid.${_tmpCounter++}.tmp');
    tmp.writeAsStringSync(content, flush: true);
    tmp.renameSync(file.path);
  }

  int _tmpCounter = 0;
}
