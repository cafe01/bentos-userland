import 'dart:io';

import '../git/git.dart';
import '../git/git_ambient.dart';
import '../git/model/commit.dart';

/// A persistent worktree standing beside an instance — **the condition of
/// being materialized**, which an instance is put into and released from rather
/// than a property it has.
///
/// The distinction is load-bearing. Git shares one object store across every
/// worktree, so history costs one copy however many stand at once; the *files*
/// do not. For small contents that is nothing; for heavy artifacts it is not.
/// So: a face keeps one of these because someone is looking, an acting body
/// takes a private [Workspace] and discards it, and everything else reads at
/// the ref with no worktree at all — which is exactly what lets a federated
/// site that only reacts hold no tree whatsoever.
///
/// **It belongs to whoever looks, not to the entity.** It necessarily lags the
/// instance — another participant may land an act at any moment — and
/// refreshing before anything writes through it is the duty of whoever uses it.
final class Materialization {
  Materialization({
    required this.directory,
    required this.gitDir,
    required this.ref,
  });

  /// Where the files stand. An ordinary directory: by the time work happens the
  /// thing is materialized and the target is a local path, which is the whole
  /// difference between a coordinate and an address.
  final Directory directory;

  final String gitDir;

  /// The ref the files follow, and **null when they follow none**: a tree
  /// standing at a commit declared from outside — a place's pin — has no tip to
  /// catch up with, and moving it is the declarer's act rather than a
  /// ref-follow. So [refresh] has nothing to do there, and says so by doing
  /// nothing.
  final String? ref;

  /// The commit the files currently stand at — not the instance's tip, which
  /// may have moved.
  ///
  /// **Asked of the disk, never held in memory.** The worktree carries its own
  /// head and the substrate answers for it, so a materialization is mountable
  /// by any process that holds the directory — which is what `entity refresh`
  /// is, three processes after the one that stood the tree up. A commit kept in
  /// a field would have been state we invented, true only for whoever
  /// constructed the object.
  ///
  /// Null when nothing of ours stands there — the honest answer for a directory
  /// already released, and for one that was never ours to begin with.
  ///
  /// **Ours, and not merely somebody's.** [ambientGit.worktreeHead] answers for
  /// a registered worktree of *whatever* repository holds it, and a place may
  /// sit inside a checkout that is nobody's business here. Asking [gitDir] by
  /// name is what makes *is this tree the one this repository stood up* a
  /// question about possession rather than about neighbourhood.
  Commit? get at =>
      _ours ? ambientGit.worktreeHead(directory.path) : null;

  /// Whether the directory is a worktree **this** repository registered.
  bool get _ours {
    final holder = ambientGit.worktreeRepository(directory.path);
    return holder != null && _resolved(holder) == _resolved(gitDir);
  }

  /// One spelling for one directory: the register answers resolved and a caller
  /// carries whatever it was handed, which differ wherever temp is a link.
  static String _resolved(String path) {
    final dir = Directory(path);
    return dir.existsSync() ? dir.resolveSymbolicLinksSync() : path;
  }

  /// Brings the files to the ref's present tip — **and stands them up when
  /// nothing stands here yet**, because a tree that was never put down and one
  /// that fell behind are the same question to whoever needs it now: *make this
  /// directory be the ref*.
  ///
  /// Three states, and the third is why this cannot be written as two:
  ///
  /// - **absent** — nothing here, or an empty directory: materialized.
  /// - **ours** — advanced, or left alone when it already stands at the tip.
  /// - **alien** — content here that this repository never registered:
  ///   [WorktreeNotOurs], loud and named. Never discarded. A verb that clears
  ///   what it does not own to make room for itself is one bad path away from
  ///   deleting a stranger's work, and the caller who put those files there is
  ///   the only one who knows what they are.
  void refresh() {
    final following = ref;
    if (following == null) return;
    final tip = ambientGit.revParse(gitDir, following);
    if (tip == null) return;
    final standing = at;
    if (standing == tip) return;
    if (standing != null) {
      ambientGit.worktreeRemove(gitDir, path: directory.path);
      ambientGit.worktreeAdd(gitDir, path: directory.path, at: tip);
      return;
    }
    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      throw WorktreeNotOurs(directory.path, repository: gitDir);
    }
    ambientGit.worktreeAdd(gitDir, path: directory.path, at: tip);
  }

  /// Discards the worktree and deregisters it. Public here — unlike in
  /// [Workspace], where the bracket owns the lifetime — because the lifetime of
  /// a face's worktree is the face's own affair and may outlive any call.
  void release() => ambientGit.worktreeRemove(gitDir, path: directory.path);
}
