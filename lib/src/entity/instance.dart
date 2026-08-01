import 'dart:async';

import 'action.dart';
import 'entity.dart';
import 'materialization.dart';
import 'model/actor.dart';
import 'model/commit.dart';
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
  Commit? get tip => throw UnimplementedError('Instance.tip');

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
  Instance create({Commit? from}) => throw UnimplementedError('Instance.create');

  /// The acts of this instance, newest first. Reading an instance's events in
  /// sequence *is* reading its log under another name, which is why an actor's
  /// context comes free with the medium.
  List<Action> get log => throw UnimplementedError('Instance.log');

  /// The bytes at [path] in this instance's tree, read **at the ref, with no
  /// worktree** — the reading a federated site that only reacts lives on.
  List<int> read(String path) => throw UnimplementedError('Instance.read');

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
  }) =>
      throw UnimplementedError('Instance.act');

  /// Opens the private area with the obligation attached — the piece of [act],
  /// for callers that cannot be a callback: the coreutil's plumbing family is
  /// three separate processes and no closure spans them. Whoever calls this
  /// owes `commit` and `release`.
  Workspace beginAct() => throw UnimplementedError('Instance.beginAct');

  /// Puts the instance into the materialized condition: a persistent worktree
  /// someone looks at. Not how an act writes — an act takes its own private
  /// area — and not something an instance needs in order to exist.
  Materialization materialize({String? at}) =>
      throw UnimplementedError('Instance.materialize');

  /// Sends this instance's ref to [remote]. The receiving side runs its own
  /// hook: the same refusal, the same wakings, at another site.
  Future<void> push(String remote) => throw UnimplementedError('Instance.push');

  /// Brings the remote's line down. Nothing is merged — divergence is
  /// legitimate, and joining two lines is an act of its own.
  Future<void> fetch(String remote) => throw UnimplementedError('Instance.fetch');

  /// The ref this instance is, fully qualified.
  String get ref => 'refs/heads/$id';

  @override
  String toString() => '${entity.name}:$id';
}
