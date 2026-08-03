import 'dart:async';
import 'dart:io';

import 'action.dart';
import 'entity.dart';
import '../git/git_ambient.dart';
import 'materialization.dart';
import '../git/model/actor.dart';
import '../git/model/commit.dart';
import 'workspace.dart';

/// One object of the class — a ref, whose state is the tree at that ref. A
/// conversation, a case, a running process of a company: one of them, with its
/// own life and its own history.
///
/// A ref is 41 bytes, so **instances cost nothing**, which is what makes
/// forking routine rather than an event. Instances do not interfere: each is
/// its own ref, and a write to one is invisible to the others until something
/// joins them.
///
/// Like every handle here it is cheap, lazy and live: `entity.instance('x')`
/// creates nothing and reads nothing, and a ref moved by another process is
/// seen on the next access.
final class Instance {
  /// A handle to the instance [id] of [entity]. Zero IO; the instance need not
  /// exist.
  Instance(this.entity, this.id);

  final Entity entity;

  /// The instance's name within the class — the second half of a coordinate.
  final String id;

  /// The commit this instance stands at, or **null until it is born**. The
  /// honest reading of a ref that does not exist, and the same value the swap
  /// takes to mean *must not exist*.
  Commit? get tip => ambientGit.revParse(_gitDir, ref);

  /// The entity's own directory. Resolved here and handed to the pieces that
  /// genuinely need it — never to a caller.
  String get _gitDir => gitDirOf(entity);

  /// Births the ref — the class's constructor.
  ///
  /// **An instance is born from a commit, always**, and its origin is an
  /// argument: from genesis (the default) comes a fresh object, empty the way a
  /// constructor leaves one; from a live commit of another instance comes a
  /// **fork**, an object that inherits a lived past. One operation, two
  /// origins, and which it was stays legible forever in the history rather than
  /// in a second verb.
  ///
  /// Neither origin is privileged and no line is the true one: whether a fork
  /// is a variant, a retry or an alternative reading is the application's word.
  Instance create({Commit? from}) {
    ambientGit.branch(_gitDir, name: id, startPoint: from ?? entity.genesis);
    return this;
  }

  /// The acts of this instance, newest first. Reading an instance's events in
  /// sequence *is* reading its log under another name, which is why an actor's
  /// context comes free with the medium.
  List<Action> get log {
    final gitDir = _gitDir;
    final at = ambientGit.revParse(gitDir, ref);
    if (at == null) return const [];
    // The walk stops at genesis: the structure an instance was born from is not
    // one of its acts, which is why birthing leaves no action behind.
    final origin = ambientGit.revParse(gitDir, Entity.genesisRef)?.sha;
    return [
      for (final record in ambientGit.log(gitDir, ref: ref))
        if (record.sha != origin)
          Action(gitDir: gitDir, ref: ref, commit: Commit(record.sha)),
    ];
  }

  /// The bytes at [path] in this instance's tree, read **at the ref, with no
  /// worktree** — the reading a federated site that only reacts lives on.
  ///
  /// [at] names a point in this instance's history and defaults to the present
  /// tip. It is not a convenience: a reader that can only see the present
  /// cannot answer *was this act legal where it was taken*, and a validator
  /// asks exactly that, at the parent of the commit landing.
  List<int> read(String path, {Commit? at}) {
    final standing = at ?? tip;
    if (standing == null) throw StateError('not born: $this');
    return ambientGit.catFile(_gitDir, '${standing.sha}:$path');
  }

  /// The paths directly under [path] in this instance's tree, sorted, read at
  /// the ref like [read] and at the same point in history.
  ///
  /// The listing half of reading. [read] hands back one path at a time, so
  /// without this any reader of composite state — a machine folded out of a
  /// directory of messages — has to leave the ontology to find out what the
  /// paths are, and the escape hatch ends up doing ordinary work.
  List<String> ls(String path, {Commit? at}) {
    final standing = at ?? tip;
    if (standing == null) throw StateError('not born: $this');
    return ambientGit.lsTree(_gitDir, at: standing, path: path);
  }

  /// Takes one action: opens a private area at the current tip, runs [body] to
  /// write into it, commits under the noun [name] with compare-and-swap, and
  /// releases the area in a `finally`.
  ///
  /// **The only safe path.** Dart has no destructor, so an exposed lifetime is
  /// a leak by construction — an orphaned directory and a worktree entry left
  /// registered. The bracket owns the lifetime; [beginAct] exists for the one
  /// shape a callback cannot serve.
  ///
  /// **It does not invoke the entity.** Nothing executes an object whose state
  /// changes by being written to: the bracket frames *the caller's own write*,
  /// and the declared [name] is what makes it an event anyone can arm on.
  ///
  /// Asynchronous by both clauses of the law — it runs a body that is not ours,
  /// and it spawns processes. Returns [Landed] or [Refused]; a lost race is a
  /// value, never a throw.
  Future<ActionResult> act(
    String name,
    FutureOr<void> Function(Workspace) body, {
    Actor? actor,
  }) async {
    final workspace = beginAct();
    try {
      await body(workspace);
      return workspace.commit(name, actor: actor);
    } finally {
      workspace.release();
    }
  }

  /// Opens the private area with the obligation attached — the piece of [act],
  /// for callers that cannot be a callback: the coreutil's plumbing family is
  /// three separate processes and no closure spans them. Whoever calls this
  /// owes `commit` and `release`.
  Workspace beginAct() {
    final gitDir = _gitDir;
    final at = ambientGit.revParse(gitDir, ref);
    if (at == null) throw StateError('not born: $this');
    // An area of its own, always. Two bodies sharing one worktree corrupt each
    // other's payload before either reaches the swap — the race the CAS exists
    // for, happening one floor below it.
    final area = Directory.systemTemp.createTempSync('entity-act-');
    area.deleteSync();
    ambientGit.worktreeAdd(gitDir, path: area.path, at: at);
    return Workspace(
      directory: Directory(area.path),
      gitDir: gitDir,
      ref: ref,
      expectedTip: at,
    );
  }

  /// Puts the instance into the materialized condition: a persistent worktree
  /// someone looks at. Not how an act writes — an act takes its own private
  /// area — and not something an instance needs in order to exist.
  Materialization materialize({String? at}) {
    final gitDir = _gitDir;
    final standing = ambientGit.revParse(gitDir, ref);
    if (standing == null) throw StateError('not born: $this');
    final path = at ??
        (Directory.systemTemp.createTempSync('entity-face-')..deleteSync()).path;
    ambientGit.worktreeAdd(gitDir, path: path, at: standing);
    return materialization(path);
  }

  /// The materialization standing at [path], **mounted from the disk** — the
  /// handle for a process that did not stand the tree up and holds only a
  /// directory.
  ///
  /// The ref comes from here and not from the tree, because a worktree of ours
  /// is detached and cannot report which instance it follows: that is the same
  /// fact `commit` names a coordinate for, and the reason `entity refresh`
  /// takes one too.
  Materialization materialization(String path) => Materialization(
        directory: Directory(path),
        gitDir: _gitDir,
        ref: ref,
      );

  /// Sends this instance's ref to [remote]. The receiving side runs its own
  /// hook: the same refusal, the same wakings, at another site.
  Future<void> push(String remote) =>
      ambientGit.push(_gitDir, remote: remote, ref: ref);

  /// Brings this instance's line down from [remote] and advances the local ref
  /// to it — **the mirror of [push]**, and the reason federation is symmetric:
  /// push moves the ref over there under the hook over there, fetch moves the
  /// ref here under the hook here. The same compare-and-swap, so a received act
  /// is validated, refused and reacted to exactly as a local one is.
  ///
  /// Nothing is merged. What lands is a line *extended* — the local tip an
  /// ancestor of what arrived, or no local tip at all, which is how an instance
  /// born at another site arrives here for the first time. Two lines that
  /// genuinely diverged are [Refused]: joining them is an act of its own, and
  /// divergence is legitimate rather than a fault to repair.
  Future<ActionResult> fetch(String remote) async {
    final gitDir = _gitDir;
    final standing = ambientGit.revParse(gitDir, ref);
    final arrived = await ambientGit.fetch(gitDir, remote: remote, ref: ref);
    if (arrived == null) {
      return Refused('no such instance at $remote', expected: standing);
    }
    if (standing != null) {
      if (standing == arrived) {
        // Already holding it. Idempotent on purpose: fetching twice is the
        // ordinary shape of a face that polls, and the second one is not a
        // refusal.
        return Landed(Action(gitDir: gitDir, ref: ref, commit: arrived));
      }
      if (!ambientGit.isAncestor(gitDir, ancestor: standing, descendant: arrived)) {
        return Refused('diverged', expected: standing, found: arrived);
      }
    }
    final moved = ambientGit.updateRef(
      gitDir,
      ref: ref,
      newCommit: arrived,
      expected: standing,
    );
    if (!moved) {
      return Refused(
        'the ref moved while fetching',
        expected: standing,
        found: ambientGit.revParse(gitDir, ref),
      );
    }
    return Landed(Action(gitDir: gitDir, ref: ref, commit: arrived));
  }

  /// The ref this instance is, fully qualified.
  String get ref => 'refs/heads/$id';

  @override
  String toString() => '${entity.name}:$id';
}
