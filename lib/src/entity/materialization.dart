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
    required Commit at,
  }) : _at = at;

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

  /// What the files stand at. Held rather than asked for: the substrate has no
  /// verb for *which commit is this worktree at*, and the answer is anyway a
  /// fact about the looker's own last act, not about the instance.
  Commit _at;

  /// The commit the files currently stand at — not the instance's tip, which
  /// may have moved.
  Commit get at => _at;

  /// Brings the files up to the instance's present tip. The duty of whoever
  /// looks; nothing does it for them.
  void refresh() {
    final following = ref;
    if (following == null) return;
    final tip = ambientGit.revParse(gitDir, following);
    if (tip == null || tip == _at) return;
    ambientGit.worktreeRemove(gitDir, path: directory.path);
    ambientGit.worktreeAdd(gitDir, path: directory.path, at: tip);
    _at = tip;
  }

  /// Discards the worktree and deregisters it. Public here — unlike in
  /// [Workspace], where the bracket owns the lifetime — because the lifetime of
  /// a face's worktree is the face's own affair and may outlive any call.
  void release() => ambientGit.worktreeRemove(gitDir, path: directory.path);
}
