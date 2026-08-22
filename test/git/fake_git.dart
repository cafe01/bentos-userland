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
class FakeGit implements Git {
  /// Every repository this fake holds, by directory. One instance stands in for
  /// a whole machine, which is what lets [clone], [push] and [fetch] be modelled
  /// at all.
  final Map<String, Repo> repos = {};

  /// Content-addressed store, shared as Git's own object store is shared.
  final Map<String, List<int>> _objects = {};
  final Map<String, String> _shaByContent = {};
  int _counter = 0;

  /// The repository at [gitDir], refusing one whose directory is gone.
  ///
  /// A repository is a **directory**, and this register is not it. Keyed by
  /// path and never pruned, the map outlived the disk: a clone taken from a
  /// staging directory that was then deleted went on answering out of memory,
  /// so a fetch from a corpse returned the sha it held at clone time instead of
  /// failing the way real Git does (exit 128). The stale answer is the
  /// dangerous shape — it is not a missing gate, it is a green gate over a
  /// repository that does not exist.
  ///
  /// The check is conditional on purpose: a repository registered at a path
  /// that never was a directory is a *fiction*, and this fake is deliberately
  /// drivable with fictional paths (`/e.git`) where nothing about the disk is
  /// under test. What must not survive is a repository that stood on the disk
  /// and no longer does — so [Repo.onDisk] records what the disk said at
  /// registration, and only that repository is asked about again.
  Repo _repo(String gitDir) {
    final repo = repos[gitDir];
    if (repo == null) throw StateError('no repository at $gitDir');
    if (repo.onDisk && !Directory(gitDir).existsSync()) {
      throw StateError('repository is gone from disk: $gitDir — '
          'this register outlived the directory, and real Git would refuse');
    }
    return repo;
  }

  /// A deterministic object name: the same content always yields the same sha,
  /// and different content never collides. Deterministic on purpose — a race
  /// test that cannot be repeated proves nothing.
  String _sha(String content) => _shaByContent.putIfAbsent(content, () {
        _counter++;
        return _counter.toRadixString(16).padLeft(40, '0');
      });

  @override
  void init(String gitDir, {bool bare = true}) {
    repos[gitDir] = Repo(bare: bare, onDisk: _lay(gitDir));
  }

  /// Lays the repository's directory down, as `git init` and `git clone` both
  /// do, and answers whether the disk accepted it. A fictional path the machine
  /// refuses (`/e.git`) is not an error here — it is a test driving this fake
  /// with names rather than places, and such a repository is simply never asked
  /// about the disk again.
  bool _lay(String gitDir) {
    try {
      Directory(gitDir).createSync(recursive: true);
      return true;
    } on FileSystemException {
      return false;
    }
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
    required Actor actor,
  }) {
    // **The stand-in for an unconfigured cascade is gone, because the cascade
    // is gone.** This double used to invent `configured@local` for a caller
    // that passed no actor, which modelled the substrate faithfully and is now
    // modelling a floor that cannot be reached: absence is not expressible.
    final instant = DateTime.utc(2026, 1, 1).add(Duration(seconds: _counter));
    final sha = _sha('commit:$tree:${parents.join('+')}:$message:${actor.name}');
    _repo(gitDir).commits[sha] = CommitObj(
      tree: tree,
      parents: parents,
      // Written as a signer, read back as a claim — the same asymmetry the
      // real substrate has, which is why the double must not keep one type for
      // both directions.
      author: Attribution(actor.name, actor.email),
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
  List<RawCommit> log(
    String gitDir, {
    required String ref,
    int? limit,
    List<String> excluding = const [],
  }) {
    final repo = _repo(gitDir);
    // Mirrors `--first-parent --not`: every exclusion's own first-parent chain
    // is ground the walk below must not cross.
    final excluded = <String>{};
    for (final exclusion in excluding) {
      var at = revParse(gitDir, exclusion)?.sha;
      while (at != null && excluded.add(at)) {
        final obj = repo.commits[at];
        at = (obj == null || obj.parents.isEmpty) ? null : obj.parents.first;
      }
    }
    final out = <RawCommit>[];
    var at = revParse(gitDir, ref)?.sha;
    while (at != null &&
        !excluded.contains(at) &&
        (limit == null || out.length < limit)) {
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
  void worktreeAdd(
    String gitDir, {
    required String path,
    required Commit at,
    String? branch,
  }) {
    final repo = _repo(gitDir);
    // Pruned first, as the real port now does: a registration whose directory
    // is gone is dead weight, and *stand this directory up again* stays one
    // act rather than a caller's separate cleanup.
    for (final registered in repo.worktrees.keys.toList()) {
      if (!Directory(registered).existsSync()) {
        repo.worktrees.remove(registered);
        heads.remove(registered);
      }
    }
    // One attached tree per branch — git's own guard, modelled honestly now
    // that nothing overrides it. A second attach is refused with the same
    // sentence real Git writes, never invented here.
    if (branch != null) {
      String? holder;
      for (final registered in repo.worktrees.keys) {
        if (heads[registered] == branch) {
          holder = registered;
          break;
        }
      }
      if (holder != null) {
        throw ProcessException(
          'git',
          ['worktree', 'add', path, branch],
          "fatal: '$branch' is already used by worktree at '$holder'",
          128,
        );
      }
    }
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
    // `heads` already drives [worktreeHead] and [currentBranch] through a
    // branch name, exactly as the real port's symref does — so recording the
    // attachment here is what makes a call through this fake self-consistent
    // rather than needing a test to inject the same fact by hand. Cleared on a
    // detached add: a path re-added without a branch stands detached again,
    // and a stale entry from an earlier attach would lie about that.
    if (branch != null) {
      heads[path] = branch;
    } else {
      heads.remove(path);
    }
  }

  @override
  List<String> worktreesOn(String gitDir, String branch) {
    final repo = _repo(gitDir);
    return [
      for (final path in repo.worktrees.keys)
        if (heads[path] == branch) path,
    ]..sort();
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
    heads.remove(path);
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  @override
  WorktreeCheckout worktreeCheckout(String path, {required Commit to}) {
    final gitDir = worktreeRepository(path);
    if (gitDir == null) throw StateError('no worktree at $path');
    final repo = _repo(gitDir);
    final standing = repo.worktrees[path];
    final target = repo.trees[repo.commits[to.sha]?.tree] ?? const {};
    // Modelled at the coarse grain the fake's scope allows: any file whose
    // bytes on disk no longer match what the *standing* commit's tree put
    // there is a local change, and any such change refuses the move — never
    // only the paths the incoming tree happens to touch. Finer than that is
    // real Git's own merge of three trees, and reimplementing it here is
    // exactly the growth this double's scope forbids.
    final onStanding = repo.trees[repo.commits[standing]?.tree] ?? const {};
    for (final entry in onStanding.entries) {
      final file = File(p.join(path, entry.key));
      final onDisk = file.existsSync() ? hashObject(gitDir, file.readAsBytesSync()) : null;
      if (onDisk != entry.value) {
        return WorktreeCheckout(
          moved: false,
          report: 'local changes to ${entry.key} would be overwritten',
        );
      }
    }
    // An untracked file — present on disk, named by neither tree — blocks the
    // move only where the incoming tree would overwrite it, exactly as real
    // Git refuses. A path the incoming tree never touches is not this move's
    // business, whatever is sitting there.
    for (final entry in target.entries) {
      if (onStanding.containsKey(entry.key)) continue;
      final file = File(p.join(path, entry.key));
      if (file.existsSync()) {
        return WorktreeCheckout(
          moved: false,
          report: 'untracked ${entry.key} would be overwritten',
        );
      }
    }
    // The move touches only what the two trees name: paths the standing tree
    // held and the incoming one drops are removed, paths the incoming tree
    // holds are written. Everything else on disk — an untracked file this
    // move never names — is left exactly where it was, as real Git leaves it.
    for (final key in onStanding.keys) {
      if (target.containsKey(key)) continue;
      final file = File(p.join(path, key));
      if (file.existsSync()) file.deleteSync();
    }
    for (final entry in target.entries) {
      final file = File(p.join(path, entry.key))..parent.createSync(recursive: true);
      file.writeAsBytesSync(_objects[entry.value]!);
    }
    File(p.join(path, '.git')).writeAsStringSync('gitdir: $gitDir\n');
    repo.worktrees[path] = to.sha;
    return const WorktreeCheckout(moved: true);
  }

  @override
  WorktreeCommit commitInWorktree(
    String path, {
    required String message,
    required Actor actor,
  }) {
    final gitDir = worktreeRepository(path);
    if (gitDir == null) throw StateError('no worktree at $path');
    final branch = heads[path];
    // A detached tree has no branch to move, and the real substrate says so
    // rather than committing into nowhere. Modelled, because the acting path
    // depends on the attachment being real: a double that committed anyway
    // would certify an act that lands nothing.
    if (branch == null) {
      throw StateError('the worktree at $path follows no branch');
    }
    // The same gate the swap models, on the path that replaced the swap: the
    // double has no hooks, so a refusal is asked for. It fires here because
    // a commit in an attached tree is a ref transaction like any other.
    final declining = declineNextSwap;
    if (declining != null) {
      declineNextSwap = null;
      return WorktreeCommit(
        report: '$declining\nfatal: ref updates aborted by hook',
      );
    }
    final repo = _repo(gitDir);
    final ref = 'refs/heads/$branch';
    final parent = repo.refs[ref];
    // Everything on disk, exactly as `add --all` then `commit` does — the
    // fake has no index, so the tree of the worktree *is* the payload.
    final tree = writeTree(gitDir, workTree: path);
    final sha = commitTree(
      gitDir,
      tree: tree,
      parents: [?parent],
      message: message,
      actor: actor,
    );
    // One transaction in the real substrate: the ref advances and the files
    // stand at what was just committed, with no window between them.
    repo.refs[ref] = sha;
    repo.worktrees[path] = sha;
    return WorktreeCommit(commit: Commit(sha));
  }

  @override
  void worktreeDiscard(String path, {required Commit to}) {
    final gitDir = worktreeRepository(path);
    if (gitDir == null) throw StateError('no worktree at $path');
    final repo = _repo(gitDir);
    final onTarget = repo.trees[repo.commits[to.sha]?.tree] ?? const {};
    final dir = Directory(path);
    // Untracked first: what the target does not name is removed, which is the
    // half `reset --hard` alone leaves behind.
    if (dir.existsSync()) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: path);
        if (p.split(rel).first == '.git') continue;
        if (!onTarget.containsKey(rel)) f.deleteSync();
      }
    }
    for (final entry in onTarget.entries) {
      final file = File(p.join(path, entry.key))
        ..parent.createSync(recursive: true);
      file.writeAsBytesSync(_objects[entry.value]!);
    }
    repo.worktrees[path] = to.sha;
  }

  @override
  List<String> worktreeDirtyPaths(String path) {
    final gitDir = worktreeRepository(path);
    if (gitDir == null) throw StateError('no worktree at $path');
    final repo = _repo(gitDir);
    final standing = repo.worktrees[path];
    final onStanding = repo.trees[repo.commits[standing]?.tree] ?? const {};
    // Coarse, as [worktreeCheckout] already is: any tracked path whose bytes
    // no longer match what the standing commit's tree put there is dirty,
    // whether the change was staged or not — the fake has no index of its
    // own to tell the two apart. Untracked is the other half: a file on disk
    // the standing tree never named.
    final dirty = <String>{};
    for (final entry in onStanding.entries) {
      final file = File(p.join(path, entry.key));
      final onDisk =
          file.existsSync() ? hashObject(gitDir, file.readAsBytesSync()) : null;
      if (onDisk != entry.value) dirty.add(entry.key);
    }
    final dir = Directory(path);
    if (dir.existsSync()) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = p.relative(f.path, from: path);
        if (p.split(rel).first == '.git') continue;
        if (!onStanding.containsKey(rel)) dirty.add(rel);
      }
    }
    return dirty.toList()..sort();
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
    // **A tree that follows a branch answers through the ref**, exactly as a
    // symref `HEAD` does — so it reads as the branch's present tip the instant
    // anything moves that ref, while [worktrees] still records where the files
    // actually stand. Modelled here because a double that answered with the
    // checked-out sha regardless made the whole class of defect inexpressible:
    // the code under test compared HEAD against the tip to decide whether to
    // check out, and against this fixture that comparison could never be
    // wrong. The trap has to exist in the double or the double certifies it.
    final branch = heads[path];
    if (branch != null) {
      final tip = repos[gitDir]?.refs['refs/heads/$branch'];
      return tip == null ? null : Commit(tip);
    }
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

  /// Makes the pin fail the way the real substrate fails it — `update-index
  /// --cacheinfo 160000` refusing over tracked blobs at the same path.
  ///
  /// The one failure a map-shaped index cannot produce on its own, and the one
  /// a caller must be judged against: it lands **inside** `register`, after the
  /// clone and after the `.gitmodules` line, which is precisely the interval
  /// where a half-installation is born.
  bool failStageGitlink = false;

  @override
  void stageGitlink(String workTree, {required String path, required Commit at}) {
    if (failStageGitlink) {
      throw ProcessException('git', ['update-index', '--cacheinfo', path],
          "'$path' appears as both a file and as a directory", 128);
    }
    (index[workTree] ??= {})[path] = (mode: '160000', sha: at.sha);
  }

  @override
  void unstageGitlink(String workTree, String path) {
    index[workTree]?.remove(path);
  }

  @override
  List<({String mode, String sha, String path})> stagedEntries(
    String workTree,
    String path,
  ) =>
      [
        for (final entry in (index[workTree] ?? const {}).entries)
          if (entry.key == path || p.isWithin(path, entry.key))
            (mode: entry.value.mode, sha: entry.value.sha, path: entry.key),
      ];

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
  void setRemoteUrl(String gitDir, {required String name, required String url}) {
    final remotes = _repo(gitDir).remotes;
    final at = remotes.indexWhere((r) => r.name == name);
    if (at < 0) {
      throw StateError(
        'no remote named $name in $gitDir — real Git exits 2 here, and a '
        'set-url that silently declared one would be addRemote wearing '
        'another name',
      );
    }
    remotes[at] = Remote(name: name, url: url);
  }

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) async {
    final from = _repo(source);
    repos[gitDir] = Repo(bare: bare, onDisk: _lay(gitDir))
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

/// A [FakeGit] that records every reach across the network — the strong
/// witness for a negative claim like *refit reaches no network*, standing
/// behind the verb under test rather than arguing the claim from the
/// signature. Empty after the call is the whole of the gate.
final class NetworkRecordingGit extends FakeGit {
  final List<String> networkCalls = [];

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) {
    networkCalls.add('clone $source -> $gitDir');
    return super.clone(source, gitDir, bare: bare);
  }

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) {
    networkCalls.add('push $gitDir -> $remote');
    return super.push(gitDir, remote: remote, ref: ref);
  }

  @override
  Future<Commit?> fetch(String gitDir,
      {required String remote, required String ref}) {
    networkCalls.add('fetch $gitDir <- $remote $ref');
    return super.fetch(gitDir, remote: remote, ref: ref);
  }
}

final class Repo {
  Repo({required this.bare, this.onDisk = false});

  final bool bare;

  /// Whether this repository's directory was actually laid down on the machine.
  /// A repository that stood on the disk and is later deleted must stop
  /// answering; one that never was a directory is a fiction and keeps answering.
  final bool onDisk;
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
  final Attribution author;
  final DateTime instant;
  final String message;
}
