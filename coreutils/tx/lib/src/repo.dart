import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A failure running a git plumbing command.
final class TxGitError extends Error {
  TxGitError(this.message);
  final String message;
  @override
  String toString() => 'tx: $message';
}

/// A `tx` operation that has no current session to act on.
final class TxNoSessionError extends Error {
  TxNoSessionError(this.message);
  final String message;
  @override
  String toString() => 'tx: $message';
}

/// The content-blind transaction log for one entity, over a real git repo at
/// [dir] (`<place>/.tx/<entity>/`).
///
/// `tx` moves history, never meaning: [append] commits the bytes it is handed
/// verbatim, [cat] streams them back. The framing (a `List<ChatMessage>` one
/// per line) is the caller's; this layer refuses to read inside the record.
final class TxRepo {
  TxRepo(this.dir, this.entity);

  /// The repo directory (`<place>/.tx/<entity>/`).
  final Directory dir;

  /// The being whose log this is — also the git author.
  final String entity;

  /// The single append-only record file. Its name is an implementation
  /// detail; the bytes inside are the caller's, never parsed here.
  static const _recordName = 'log';

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  File get _record => File('${dir.path}/$_recordName');

  /// Opens a fresh session, makes it current, and returns its id.
  ///
  /// A session is an orphan branch — a fresh, independent line of history with
  /// an empty record. (Branching an *existing* line is `fork`, D2.)
  Future<String> newSession() async {
    await _ensureInit();
    final sid = _generateSid();
    await _git(['checkout', '-q', '--orphan', sid]);
    // An orphan checkout keeps the prior branch's files staged; drop them so
    // the new line starts from an empty record.
    await _git(['reset', '-q']);
    _record.writeAsBytesSync(Uint8List(0));
    await _git(['add', _recordName]);
    await _commit('tx new $sid');
    return sid;
  }

  /// Appends [bytes] to the current session and commits — one append, one
  /// commit (the write-ahead property). Content-blind: bytes are stored
  /// verbatim, never decoded.
  Future<void> append(List<int> bytes) async {
    _requireSession();
    _record.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);
    await _git(['add', _recordName]);
    // --allow-empty so the one-append-one-commit invariant holds even for a
    // zero-byte append: the mutation still earns a commit / resume point.
    await _commit('tx append', allowEmpty: true);
  }

  /// Streams the current session's accumulated bytes. Content-blind — the
  /// caller decodes. Empty if the session has no appends yet.
  Uint8List cat() {
    _requireSession();
    if (!_record.existsSync()) return Uint8List(0);
    return _record.readAsBytesSync();
  }

  // --- internals -----------------------------------------------------------

  bool get _initialized => Directory('${dir.path}/.git').existsSync();

  void _requireSession() {
    if (!_initialized) {
      throw TxNoSessionError(
        'no session for "$entity". Run `tx new` first.',
      );
    }
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    dir.createSync(recursive: true);
    await _git(['init', '-q']);
    // Local identity so commits never depend on the operator's global config.
    await _git(['config', 'user.name', entity]);
    await _git(['config', 'user.email', '$entity@bentos']);
  }

  Future<void> _commit(String message, {bool allowEmpty = false}) =>
      _git(['commit', '-q', if (allowEmpty) '--allow-empty', '-m', message]);

  String _generateSid() {
    final rng = Random.secure();
    return List.generate(8, (_) => _alphabet[rng.nextInt(_alphabet.length)])
        .join();
  }

  Future<void> _git(List<String> args) async {
    final result = await Process.run(
      'git',
      ['-C', dir.path, ...args],
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      final err = String.fromCharCodes(result.stderr as List<int>).trim();
      throw TxGitError('git ${args.join(' ')} failed: $err');
    }
  }
}
