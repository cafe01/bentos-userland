import 'dart:io';

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
  /// already released.
  Commit? get at => ambientGit.worktreeHead(directory.path);

  /// Brings the files up to the instance's present tip. The duty of whoever
  /// looks; nothing does it for them.
  void refresh() {
    final following = ref;
    if (following == null) return;
    final tip = ambientGit.revParse(gitDir, following);
    if (tip == null || tip == at) return;
    ambientGit.worktreeRemove(gitDir, path: directory.path);
    ambientGit.worktreeAdd(gitDir, path: directory.path, at: tip);
  }

  /// Discards the worktree and deregisters it. Public here — unlike in
  /// [Workspace], where the bracket owns the lifetime — because the lifetime of
  /// a face's worktree is the face's own affair and may outlive any call.
  void release() => ambientGit.worktreeRemove(gitDir, path: directory.path);
}
