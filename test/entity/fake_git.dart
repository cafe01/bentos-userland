import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;

/// An in-memory [Git] — **the design's own infrastructure**, and the collaborator
/// the contract suite runs against.
///
/// # Why it exists
///
/// `IOOverrides` does not reach subprocesses, so the hermeticity `Place` gets
/// free from the platform has to be authored for the entity. This is the other
/// half of that seam: the port abstracts the substrate, and this stands in for
/// it.
///
/// # Why it is scoped exactly to the port's verbs
///
/// A double that grows past them has reimplemented Git, and its green is worth
/// nothing. So: content-addressed objects, refs with a compare-and-swap,
/// worktrees written as real files, and no index, no packs, no merge, no
/// network. Everything it does model, it models **honestly** — most of all the
/// swap, because the whole action primitive rests on it.
///
/// It is deliberately functional and not a stub: the contract suite is red today
/// against unimplemented bodies, and the day construction fills them in, the
/// suite must go green without one assertion being touched. That only works if
/// the collaborator was real all along.
final class FakeGit implements Git {
  /// Every repository this fake holds, by directory. One instance stands in for
  /// a whole machine, which is what lets [clone], [push] and [fetch] be modelled
  /// at all.
  final Map<String, Repo> repos = {};

  /// Content-addressed store, shared as Git's own object store is shared.
  final Map<String, List<int>> _objects = {};
  final Map<String, String> _shaByContent = {};
  int _counter = 0;

  Repo _repo(String gitDir) =>
      repos[gitDir] ?? (throw StateError('no repository at $gitDir'));

  /// A deterministic object name: the same content always yields the same sha,
  /// and different content never collides. Deterministic on purpose — a race
  /// test that cannot be repeated proves nothing.
  String _sha(String content) => _shaByContent.putIfAbsent(content, () {
        _counter++;
        return _counter.toRadixString(16).padLeft(40, '0');
      });

  @override
  void init(String gitDir, {bool bare = true}) {
    repos[gitDir] = Repo(bare: bare);
  }

  @override
  String hashObject(String gitDir, List<int> bytes) {
    final sha = _sha('blob:${base64.encode(bytes)}');
    _objects[sha] = bytes;
    return sha;
  }

  @override
  List<int> catFile(String gitDir, String object) {
    final colon = object.indexOf(':');
    if (colon < 0) {
      final bytes = _objects[object];
      if (bytes == null) throw StateError('no such object: $object');
      return bytes;
    }
    final rev = object.substring(0, colon);
    final path = object.substring(colon + 1);
    final commit = revParse(gitDir, rev);
    if (commit == null) throw StateError('no such rev: $rev');
    final tree = _repo(gitDir).trees[_repo(gitDir).commits[commit.sha]!.tree]!;
    final blob = tree[path];
    if (blob == null) throw StateError('no such path: $path at $rev');
    return _objects[blob]!;
  }

  @override
  String writeTree(String gitDir, {required String workTree}) {
    final entries = <String, String>{};
    final dir = Directory(workTree);
    if (dir.existsSync()) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: workTree);
        if (p.split(rel).first == '.git') continue;
        entries[rel] = hashObject(gitDir, f.readAsBytesSync());
      }
    }
    final key = (entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value}')
        .join(',');
    final sha = _sha('tree:$key');
    _repo(gitDir).trees[sha] = entries;
    return sha;
  }

  @override
  String commitTree(
    String gitDir, {
    required String tree,
    required List<String> parents,
    required String message,
    Actor? actor,
  }) {
    final who = actor ?? const Actor('unknown');
    final instant = DateTime.utc(2026, 1, 1).add(Duration(seconds: _counter));
    final sha = _sha('commit:$tree:${parents.join('+')}:$message:${who.name}');
    _repo(gitDir).commits[sha] = CommitObj(
      tree: tree,
      parents: parents,
      author: who,
      instant: instant,
      message: message,
    );
    return sha;
  }

  @override
  bool updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  }) {
    final repo = _repo(gitDir);
    final current = repo.refs[ref];
    // The swap, modelled exactly: a null expectation means the ref must not
    // exist, and any disagreement refuses rather than throws.
    if (expected == null && current != null) return false;
    if (expected != null && current != expected.sha) return false;
    repo.refs[ref] = newCommit.sha;
    return true;
  }

  @override
  void branch(String gitDir, {required String name, required Commit startPoint}) {
    _repo(gitDir).refs['refs/heads/$name'] = startPoint.sha;
  }

  @override
  List<String> branches(String gitDir) => (_repo(gitDir)
          .refs
          .keys
          .where((r) => r.startsWith('refs/heads/'))
          .map((r) => r.substring('refs/heads/'.length))
          .toList())
      ..sort();

  @override
  Commit? revParse(String gitDir, String rev) {
    final repo = _repo(gitDir);
    final direct = repo.refs[rev] ?? repo.refs['refs/heads/$rev'];
    if (direct != null) return Commit(direct);
    return repo.commits.containsKey(rev) ? Commit(rev) : null;
  }

  @override
  List<RawCommit> log(String gitDir, {required String ref, int? limit}) {
    final repo = _repo(gitDir);
    final out = <RawCommit>[];
    var at = revParse(gitDir, ref)?.sha;
    while (at != null && (limit == null || out.length < limit)) {
      final obj = repo.commits[at];
      if (obj == null) break;
      out.add(_raw(at, obj));
      at = obj.parents.isEmpty ? null : obj.parents.first;
    }
    return out;
  }

  @override
  RawCommit showCommit(String gitDir, Commit commit) {
    final obj = _repo(gitDir).commits[commit.sha];
    if (obj == null) throw StateError('no such commit: ${commit.sha}');
    return _raw(commit.sha, obj);
  }

  @override
  Diff diffTree(String gitDir, {required Commit from, required Commit to}) {
    final repo = _repo(gitDir);
    final a = repo.trees[repo.commits[from.sha]?.tree] ?? const {};
    final b = repo.trees[repo.commits[to.sha]?.tree] ?? const {};
    final changes = <Change>[];
    for (final path in {...a.keys, ...b.keys}.toList()..sort()) {
      if (!a.containsKey(path)) {
        changes.add(Change(path: path, kind: ChangeKind.added));
      } else if (!b.containsKey(path)) {
        changes.add(Change(path: path, kind: ChangeKind.deleted));
      } else if (a[path] != b[path]) {
        changes.add(Change(path: path, kind: ChangeKind.modified));
      }
    }
    return Diff(changes);
  }

  @override
  void worktreeAdd(String gitDir, {required String path, required Commit at}) {
    final repo = _repo(gitDir);
    final tree = repo.trees[repo.commits[at.sha]?.tree] ?? const {};
    Directory(path).createSync(recursive: true);
    for (final entry in tree.entries) {
      final file = File(p.join(path, entry.key))
        ..parent.createSync(recursive: true);
      file.writeAsBytesSync(_objects[entry.value]!);
    }
    repo.worktrees[path] = at.sha;
  }

  @override
  void worktreeRemove(String gitDir, {required String path}) {
    _repo(gitDir).worktrees.remove(path);
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  @override
  String? worktreeRepository(String path) {
    for (final entry in repos.entries) {
      if (entry.value.worktrees.containsKey(path)) return entry.key;
    }
    return null;
  }

  @override
  List<Remote> remotes(String gitDir) => _repo(gitDir).remotes.toList();

  @override
  void addRemote(String gitDir, {required String name, required String url}) {
    _repo(gitDir).remotes.add(Remote(name: name, url: url));
  }

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) async {
    final from = _repo(source);
    repos[gitDir] = Repo(bare: bare)
      ..refs.addAll(from.refs)
      ..commits.addAll(from.commits)
      ..trees.addAll(from.trees)
      ..remotes.add(Remote(name: 'origin', url: source));
  }

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) async {
    final url = _repo(gitDir).remotes.firstWhere((r) => r.name == remote).url;
    final target = _repo(url);
    final from = _repo(gitDir);
    target.commits.addAll(from.commits);
    target.trees.addAll(from.trees);
    for (final entry in from.refs.entries) {
      if (ref == null || entry.key == ref) target.refs[entry.key] = entry.value;
    }
  }

  @override
  Future<void> fetch(String gitDir, {required String remote}) async {
    final url = _repo(gitDir).remotes.firstWhere((r) => r.name == remote).url;
    final source = _repo(url);
    final into = _repo(gitDir);
    into.commits.addAll(source.commits);
    into.trees.addAll(source.trees);
    for (final entry in source.refs.entries) {
      into.refs['refs/remotes/$remote/${p.basename(entry.key)}'] = entry.value;
    }
  }

  RawCommit _raw(String sha, CommitObj obj) => RawCommit(
        sha: sha,
        parents: obj.parents,
        author: obj.author,
        instant: obj.instant,
        message: obj.message,
      );
}

final class Repo {
  Repo({required this.bare});

  final bool bare;
  final Map<String, String> refs = {};
  final Map<String, CommitObj> commits = {};
  final Map<String, Map<String, String>> trees = {};
  final Map<String, String> worktrees = {};
  final List<Remote> remotes = [];
}

final class CommitObj {
  CommitObj({
    required this.tree,
    required this.parents,
    required this.author,
    required this.instant,
    required this.message,
  });

  final String tree;
  final List<String> parents;
  final Actor author;
  final DateTime instant;
  final String message;
}
