import 'package:bentos_userland/entity.dart';

import 'helpers.dart';

/// What one run of the coreutil left behind: the two streams and the number the
/// process would have exited with.
typedef Run = ({String out, String err, int code});

/// The coreutil driven **in process** — no spawn, no PATH, no binary.
///
/// [EntityRunner] takes its streams and its working directory as arguments
/// precisely so that this is possible: the surface under test is the runner,
/// and a subprocess would only add a shell between the assertion and the thing
/// it is asserting about. What Tier C proves about the real substrate is proven
/// elsewhere; the port here is the fake, installed as the ambient for the whole
/// call, exactly as it is for a library test.
final class Cli {
  Cli(this.site, {Git? git}) : git = git ?? site.git;

  final Site site;
  final Git git;

  Future<Run> run(List<String> args, {String? cwd}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = EntityRunner(
      out: out,
      err: err,
      currentDirectory: cwd ?? site.root.path,
    );
    await runWithGitAsync(git, () => runner.run(args));
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }
}

/// A [Git] that lets a boundary-level test install a seam inside the port —
/// the same device [installation_life_test.dart]'s `_WatchedGit` uses at the
/// library level, needed here because a contested swap is a claim about the
/// interval between the read and the swap, which an end state cannot hold.
final class WatchedGit implements Git {
  WatchedGit(this._inner);

  final Git _inner;

  /// Runs after the fetch has returned — where a concurrent actor really
  /// could land, and therefore where a lost swap is made genuine.
  void Function()? afterFetch;

  @override
  Future<Commit?> fetch(String gitDir,
      {required String remote, required String ref}) async {
    final at = await _inner.fetch(gitDir, remote: remote, ref: ref);
    afterFetch?.call();
    return at;
  }

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) =>
      _inner.clone(source, gitDir, bare: bare);

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) =>
      _inner.push(gitDir, remote: remote, ref: ref);

  @override
  RefUpdate updateRef(String gitDir,
          {required String ref,
          required Commit newCommit,
          required Commit? expected}) =>
      _inner.updateRef(gitDir, ref: ref, newCommit: newCommit, expected: expected);

  @override
  void stageGitlink(String workTree, {required String path, required Commit at}) =>
      _inner.stageGitlink(workTree, path: path, at: at);

  // Every other verb this seam has no opinion about — a plain forward, spelled
  // out rather than routed through `noSuchMethod`, which dispatches on the
  // wrapper's own missing member and never reaches `_inner`'s real one.
  @override
  void init(String gitDir, {bool bare = true}) => _inner.init(gitDir, bare: bare);

  @override
  String hashObject(String gitDir, List<int> bytes) =>
      _inner.hashObject(gitDir, bytes);

  @override
  List<int> catFile(String gitDir, String object) => _inner.catFile(gitDir, object);

  @override
  List<String> lsTree(String gitDir, {required Commit at, required String path}) =>
      _inner.lsTree(gitDir, at: at, path: path);

  @override
  bool isAncestor(String gitDir,
          {required Commit ancestor, required Commit descendant}) =>
      _inner.isAncestor(gitDir, ancestor: ancestor, descendant: descendant);

  @override
  String writeTree(String gitDir, {required String workTree}) =>
      _inner.writeTree(gitDir, workTree: workTree);

  @override
  String commitTree(String gitDir,
          {required String tree,
          required List<String> parents,
          required String message,
          Actor? actor}) =>
      _inner.commitTree(gitDir,
          tree: tree, parents: parents, message: message, actor: actor);

  @override
  void branch(String gitDir, {required String name, required Commit startPoint}) =>
      _inner.branch(gitDir, name: name, startPoint: startPoint);

  @override
  List<String> branches(String gitDir) => _inner.branches(gitDir);

  @override
  Commit? revParse(String gitDir, String rev) => _inner.revParse(gitDir, rev);

  @override
  List<RawCommit> log(
    String gitDir, {
    required String ref,
    int? limit,
    List<String> excluding = const [],
  }) =>
      _inner.log(gitDir, ref: ref, limit: limit, excluding: excluding);

  @override
  RawCommit showCommit(String gitDir, Commit commit) =>
      _inner.showCommit(gitDir, commit);

  @override
  Diff diffTree(String gitDir, {required Commit from, required Commit to}) =>
      _inner.diffTree(gitDir, from: from, to: to);

  @override
  void worktreeAdd(String gitDir, {required String path, required Commit at}) =>
      _inner.worktreeAdd(gitDir, path: path, at: at);

  @override
  void worktreeRemove(String gitDir, {required String path}) =>
      _inner.worktreeRemove(gitDir, path: path);

  @override
  String? worktreeRepository(String path) => _inner.worktreeRepository(path);

  @override
  Commit? worktreeHead(String path) => _inner.worktreeHead(path);

  @override
  String? topLevel(String path) => _inner.topLevel(path);

  @override
  String? currentBranch(String workTree) => _inner.currentBranch(workTree);

  @override
  List<String> branchesIn(String workTree) => _inner.branchesIn(workTree);

  @override
  Commit? stagedGitlink(String workTree, String path) =>
      _inner.stagedGitlink(workTree, path);

  @override
  List<Remote> remotes(String gitDir) => _inner.remotes(gitDir);

  @override
  void addRemote(String gitDir, {required String name, required String url}) =>
      _inner.addRemote(gitDir, name: name, url: url);

  @override
  void setRemoteUrl(String gitDir, {required String name, required String url}) =>
      _inner.setRemoteUrl(gitDir, name: name, url: url);
}
