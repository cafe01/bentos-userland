import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/git.dart';
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
  List<String> lsTree(
    String gitDir, {
    required Commit at,
    required String path,
  }) {
    final repo = _repo(gitDir);
    final tree = repo.trees[repo.commits[at.sha]?.tree] ?? const {};
    final prefix = path.isEmpty || path.endsWith('/') ? path : '$path/';
    // One level deep, as the substrate lists it: what lies under a directory
    // entry is that entry's own listing, not this one's.
    final names = <String>{};
    for (final entry in tree.keys) {
      if (!entry.startsWith(prefix)) continue;
      final rest = entry.substring(prefix.length);
      if (rest.isEmpty) continue;
      final cut = rest.indexOf('/');
      names.add(cut < 0 ? '$prefix$rest' : '$prefix${rest.substring(0, cut)}');
    }
    return names.toList()..sort();
  }

  @override
  bool isAncestor(
    String gitDir, {
    required Commit ancestor,
    required Commit descendant,
  }) {
    final repo = _repo(gitDir);
    for (String? at = descendant.sha; at != null;) {
      if (at == ancestor.sha) return true;
      final obj = repo.commits[at];
      at = (obj == null || obj.parents.isEmpty) ? null : obj.parents.first;
    }
    return false;
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
    // No actor means the real floor passes no identity and Git's own cascade
    // answers. The double has no config to cascade through, so it stands in for
    // one — never for an invented author, which is the defect this fake would
    // otherwise keep testifying to.
    final who = actor ?? const Actor('configured', email: 'configured@local');
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
  RefUpdate updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  }) {
    // A gate standing at this swap. The double has no hooks, so refusal by one
    // is asked for rather than provoked — and what it reports is the message
    // Git itself writes, taken from a real `reference-transaction` hook exiting
    // non-zero, never a sentence invented here.
    final declining = declineNextSwap;
    if (declining != null) {
      declineNextSwap = null;
      return RefUpdate(
        moved: false,
        report: '$declining\nfatal: ref updates aborted by hook',
      );
    }
    final repo = _repo(gitDir);
    final current = repo.refs[ref];
    // The swap, modelled exactly: a null expectation means the ref must not
    // exist, and any disagreement refuses rather than throws. The report is
    // Git's own for a lost race — the word `hook` is absent from it, which is
    // the whole of what tells the two refusals apart.
    if (expected == null && current != null) {
      return RefUpdate(
        moved: false,
        report: "fatal: cannot lock ref '$ref': reference already exists",
      );
    }
    if (expected != null && current != expected.sha) {
      return RefUpdate(
        moved: false,
        report: "fatal: cannot lock ref '$ref': is at "
            "${current ?? 'nothing'} but expected ${expected.sha}",
      );
    }
    repo.refs[ref] = newCommit.sha;
    return const RefUpdate(moved: true);
  }

  /// What a gate will write to stderr the next time a swap is attempted, after
  /// which that swap is refused by the hook and this is cleared. Null is the
  /// ordinary state: no gate stands anywhere.
  String? declineNextSwap;

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
    // The marker the substrate itself writes, and the reason possession is a
    // question about the disk rather than about a register: `git worktree list`
    // keeps listing a directory somebody deleted, and a directory recreated in
    // its place carries no marker and belongs to nobody. Modelled here because
    // a double whose register outlives the disk answers *the tree stands at the
    // tip* about a tree that is not there — which is a green saying nothing
    // about the machine. [writeTree] already skips `.git`, exactly as Git does.
    File(p.join(path, '.git')).writeAsStringSync('gitdir: $gitDir\n');
    repo.worktrees[path] = at.sha;
  }

  @override
  void worktreeRemove(String gitDir, {required String path}) {
    // The same claim the real port makes before it deletes anything. Modelled
    // here because the fake is the only substrate most of this suite ever meets:
    // a double that deletes what the machine refuses to is a green that says
    // nothing about the machine.
    if (_repo(gitDir).worktrees.remove(path) == null) {
      throw WorktreeNotOurs(path, repository: gitDir);
    }
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  @override
  String? worktreeRepository(String path) {
    // Possession is two claims and the port makes both: the directory says
    // which repository laid it down, and that repository's register agrees.
    // Either alone is satisfied by a stranger's directory or by a stale entry.
    final marker = File(p.join(path, '.git'));
    if (!marker.existsSync()) return null;
    final declared = marker.readAsStringSync().trim();
    if (!declared.startsWith('gitdir: ')) return null;
    final gitDir = declared.substring('gitdir: '.length);
    return repos[gitDir]?.worktrees.containsKey(path) ?? false ? gitDir : null;
  }

  @override
  Commit? worktreeHead(String path) {
    final gitDir = worktreeRepository(path);
    if (gitDir == null) return null;
    final standing = repos[gitDir]?.worktrees[path];
    return standing == null ? null : Commit(standing);
  }

  // -------------------------------------------------------- the superproject

  /// The working trees this fake machine knows to be repositories — declared by
  /// a test, because *is this directory inside a repository* is a fact about
  /// the world and not about the ontology.
  final Set<String> workTrees = {};

  /// Staged entries, by working tree and path: mode and object name. Modelled
  /// as an index and not as a tree, because the pin stops at the index — the
  /// commit belongs to whoever inhabits the place.
  final Map<String, Map<String, ({String mode, String sha})>> index = {};

  @override
  String? topLevel(String path) {
    final matches = [
      for (final root in workTrees)
        if (p.equals(root, path) || p.isWithin(root, path)) root,
    ]..sort((a, b) => b.length.compareTo(a.length));
    return matches.isEmpty ? null : matches.first;
  }

  /// The branches of each declared working tree, and which one is checked out
  /// — a fact about the containing repository, which this fake models only as
  /// far as the superproject's half asks about it.
  final Map<String, List<String>> branchNames = {};
  final Map<String, String?> heads = {};

  @override
  String? currentBranch(String workTree) => heads[workTree];

  @override
  List<String> branchesIn(String workTree) =>
      [...?branchNames[workTree]]..sort();

  @override
  void stageGitlink(String workTree, {required String path, required Commit at}) {
    (index[workTree] ??= {})[path] = (mode: '160000', sha: at.sha);
  }

  @override
  Commit? stagedGitlink(String workTree, String path) {
    final entry = index[workTree]?[path];
    if (entry == null || entry.mode != '160000') return null;
    return Commit(entry.sha);
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
  Future<Commit?> fetch(
    String gitDir, {
    required String remote,
    required String ref,
  }) async {
    final declared = _repo(gitDir).remotes.where((r) => r.name == remote);
    final url = declared.isEmpty ? remote : declared.first.url;
    final source = _repo(url);
    final into = _repo(gitDir);
    // The objects arrive; no ref of this repository moves. What the caller
    // does with the line it received is the ontology's word.
    into.commits.addAll(source.commits);
    into.trees.addAll(source.trees);
    final there = source.refs[ref];
    return there == null ? null : Commit(there);
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
