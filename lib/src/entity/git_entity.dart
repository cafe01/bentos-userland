/// The floor, concretely: an entity IS a repository. Its state is the tree at a
/// ref, its story is the commit log, its transactions are commits, and the only
/// reaction primitive is a hook consulting a subscription table.
///
/// Nothing here is an application. What an application adds is the meaning of a
/// path, the vocabulary of a commit message, and what a woken subscriber does.
///
/// Every write is plumbing — `hash-object` / `write-tree` / `commit-tree` /
/// `update-ref` — because only `update-ref <ref> <new> <old>` gives the
/// compare-and-swap the actor model rests on. Porcelain `git commit` has no
/// expected-parent, so two bodies raised for one occurrence would both land.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A materialized worktree — path → contents. What a view renders and what a
/// woken actor folds; the entity's state, not a checkpoint of it.
typedef Tree = Map<String, String>;

/// A git command against an entity failed.
final class EntityGitError implements Exception {
  EntityGitError(this.message);

  final String message;

  @override
  String toString() => 'entity: $message';
}

/// Lost the compare-and-swap on the ref: another body committed first. The
/// loser re-folds; correctness is held by the log, and what it paid for its
/// turn is the residue.
final class RefRaceLost implements Exception {
  RefRaceLost(this.ref, this.detail);

  final String ref;
  final String detail;

  @override
  String toString() => 'RefRaceLost($ref): $detail';
}

/// One transaction: which actor did what, with what payload. The author is the
/// actor's identity — git's own author field — the message is the semantic
/// line, and the tree is the state it left.
final class Transaction {
  const Transaction({
    required this.id,
    required this.treeId,
    required this.parent,
    required this.author,
    required this.message,
  });

  /// The commit sha.
  final String id;

  /// The tree sha — the state this transaction left.
  final String treeId;

  final String? parent;
  final String author;
  final String message;

  /// The leading word of the message — the transaction's kind. A woken actor
  /// folds the machine out of these; nothing stores it.
  String get kind => message.trim().split(' ').first;

  @override
  String toString() => '$kind($author): $message';
}

/// What a transaction changed — derived from the commit, never stored.
typedef TreeDiff = ({Set<String> added, Set<String> changed, Set<String> removed});

/// Field and record separators for the log format — chosen because a commit
/// message may contain anything a person types, newlines included.
const String _fs = '\x1f';
const String _rs = '\x1e';
const String _nul = '\x00';

/// A repository, addressed as an entity.
final class GitEntity {
  GitEntity(this.dir);

  final Directory dir;

  String get path => dir.path;

  Directory get gitDir => Directory(p.join(dir.path, '.git'));

  /// The subsystem's own corner of the git dir: arming lives here, not in the
  /// tree. It is deployment, not entity state — untracked by construction, and
  /// per-clone, which is what lets two sites arm the same entity differently.
  Directory get armingDir => Directory(p.join(gitDir.path, 'bentos'));

  static int _indexSeq = 0;

  /// Creates the repository. [defaultBranch] is checked out but unborn: the
  /// first transaction is an ordinary commit with no parent.
  static Future<GitEntity> init(
    Directory dir, {
    String defaultBranch = 'main',
  }) async {
    dir.createSync(recursive: true);
    final entity = GitEntity(dir);
    await entity._run(['init', '-q', '-b', defaultBranch, '.']);
    return entity;
  }

  /// Opens an existing repository.
  static GitEntity open(Directory dir) {
    if (!Directory(p.join(dir.path, '.git')).existsSync()) {
      throw EntityGitError('no entity at "${dir.path}"');
    }
    return GitEntity(dir);
  }

  /// The tip of [ref], or null when the ref does not exist yet.
  Future<String?> head(String ref) async {
    try {
      return (await _run(['rev-parse', '--verify', '-q', ref])).trim();
    } on EntityGitError {
      return null;
    }
  }

  /// The whole state at a ref or commit — the worktree, read from the store so
  /// that a ref nobody has checked out folds exactly like one that is.
  Future<Tree> tree(String ref) async {
    final String listing;
    try {
      listing = await _run(['ls-tree', '-r', '-z', ref]);
    } on EntityGitError {
      return <String, String>{};
    }
    final paths = <String, String>{}; // path → blob sha
    for (final record in listing.split(_nul)) {
      if (record.isEmpty) continue;
      final tab = record.indexOf('\t');
      final fields = record.substring(0, tab).split(' ');
      paths[record.substring(tab + 1)] = fields[2];
    }
    final blobs = await _blobs(paths.values.toSet().toList());
    return {for (final e in paths.entries) e.key: blobs[e.value]!};
  }

  /// Oldest first — the entity's whole reality, replayed in its own words.
  Future<List<Transaction>> log(String ref) async {
    final String out;
    try {
      out = await _run(['log', '--format=%H$_fs%T$_fs%P$_fs%an$_fs%B$_rs', ref]);
    } on EntityGitError {
      return const [];
    }
    final txs = <Transaction>[];
    for (final record in out.split(_rs)) {
      final trimmed = record.trim();
      if (trimmed.isEmpty) continue;
      final f = trimmed.split(_fs);
      final parents = f[2].trim();
      txs.insert(
        0,
        Transaction(
          id: f[0],
          treeId: f[1],
          parent: parents.isEmpty ? null : parents.split(' ').first,
          author: f[3],
          message: f[4].trim(),
        ),
      );
    }
    return txs;
  }

  /// The commit, with the ref update as a compare-and-swap: [expectedParent]
  /// must still be the tip — null meaning the ref must not exist — or the write
  /// is refused with [RefRaceLost].
  ///
  /// [author] is the actor's identity and lands as git's author. The worktree
  /// is re-materialized when the ref that moved is the checked-out one, so the
  /// entity stays legible on disk.
  Future<Transaction> commit({
    required String ref,
    required String? expectedParent,
    required String author,
    required String message,
    required Tree tree,
  }) async {
    final indexFile = p.join(gitDir.path, 'bentos-index-$pid-${_indexSeq++}');
    final String treeSha;
    try {
      final entries = StringBuffer();
      for (final entry in tree.entries) {
        final blob =
            (await _run(['hash-object', '-w', '--stdin'], input: entry.value)).trim();
        entries.writeln('100644 $blob\t${entry.key}');
      }
      await _run(
        ['update-index', '--index-info'],
        input: entries.toString(),
        env: {'GIT_INDEX_FILE': indexFile},
      );
      treeSha = (await _run(['write-tree'], env: {'GIT_INDEX_FILE': indexFile})).trim();
    } finally {
      final f = File(indexFile);
      if (f.existsSync()) f.deleteSync();
    }

    final commitSha = (await _run(
      [
        'commit-tree',
        treeSha,
        if (expectedParent != null) ...['-p', expectedParent],
        '-m',
        message,
      ],
      env: _identity(author),
    ))
        .trim();

    try {
      await _run(['update-ref', ref, commitSha, expectedParent ?? '']);
    } on EntityGitError catch (e) {
      throw RefRaceLost(ref, e.message);
    }
    await _materialize(ref);

    return Transaction(
      id: commitSha,
      treeId: treeSha,
      parent: expectedParent,
      author: author,
      message: message,
    );
  }

  /// A second ref over the same history — what an application calls a fork.
  /// Parentage is the shared history, never an invented field.
  Future<void> branch({required String ref, required String at}) async {
    try {
      await _run(['update-ref', ref, at, '']);
    } on EntityGitError catch (e) {
      throw RefRaceLost(ref, e.message);
    }
  }

  /// What one transaction changed.
  Future<TreeDiff> diff(String commitId) async {
    final out = await _run(
      ['diff-tree', '-r', '--root', '--no-commit-id', '--name-status', '-z', commitId],
    );
    final fields = out.split(_nul).where((s) => s.isNotEmpty).toList();
    final added = <String>{};
    final changed = <String>{};
    final removed = <String>{};
    for (var i = 0; i + 1 < fields.length; i += 2) {
      final status = fields[i];
      final path = fields[i + 1];
      switch (status[0]) {
        case 'A':
          added.add(path);
        case 'D':
          removed.add(path);
        default:
          changed.add(path);
      }
    }
    return (added: added, changed: changed, removed: removed);
  }

  // --- internals ------------------------------------------------------------

  String? _headRef;

  /// Sync the working tree to a ref that just moved, when it is the one checked
  /// out. Plumbing on purpose: `read-tree -u --reset` touches no ref, so the
  /// materialization cannot wake anybody. Best-effort — the ref is the truth
  /// and the worktree is its projection, so a lost race here costs nothing.
  Future<void> _materialize(String ref) async {
    _headRef ??= (await _run(['symbolic-ref', '-q', 'HEAD'])).trim();
    if (_headRef != ref) return;
    try {
      await _run(['read-tree', '-u', '--reset', ref]);
    } on EntityGitError {
      // Another body is materializing the same tip; its result is ours.
    }
  }

  Map<String, String> _identity(String author) => {
        'GIT_AUTHOR_NAME': author,
        'GIT_AUTHOR_EMAIL': '$author@bentos',
        'GIT_COMMITTER_NAME': author,
        'GIT_COMMITTER_EMAIL': '$author@bentos',
      };

  /// Read many blobs in one process — a fold costs one `cat-file`, not one per
  /// message.
  Future<Map<String, String>> _blobs(List<String> shas) async {
    if (shas.isEmpty) return {};
    final proc = await Process.start('git', ['-C', dir.path, 'cat-file', '--batch']);
    final bytesFuture = proc.stdout.expand((chunk) => chunk).toList();
    final errFuture = proc.stderr.transform(utf8.decoder).join();
    proc.stdin.write(shas.map((s) => '$s\n').join());
    await proc.stdin.close();
    final bytes = await bytesFuture;
    final err = await errFuture;
    if (await proc.exitCode != 0) throw EntityGitError('cat-file: ${err.trim()}');

    final out = <String, String>{};
    var at = 0;
    for (final sha in shas) {
      // "<sha> <type> <size>\n" then <size> bytes then "\n".
      final nl = bytes.indexOf(10, at);
      final header = utf8.decode(bytes.sublist(at, nl));
      final size = int.parse(header.split(' ').last);
      final start = nl + 1;
      out[sha] = utf8.decode(bytes.sublist(start, start + size));
      at = start + size + 1;
    }
    return out;
  }

  Future<String> _run(
    List<String> args, {
    String? input,
    Map<String, String>? env,
  }) async {
    final proc = await Process.start(
      'git',
      ['-C', dir.path, ...args],
      environment: env == null ? null : {...Platform.environment, ...env},
    );
    final outFuture = proc.stdout.transform(utf8.decoder).join();
    final errFuture = proc.stderr.transform(utf8.decoder).join();
    if (input != null) proc.stdin.write(input);
    await proc.stdin.close();
    final out = await outFuture;
    final err = await errFuture;
    if (await proc.exitCode != 0) {
      throw EntityGitError('git ${args.join(' ')} failed: ${err.trim()}');
    }
    return out;
  }
}
