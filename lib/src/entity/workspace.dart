import 'dart:io';

import 'action.dart';
import 'model/actor.dart';
import 'model/commit.dart';

/// The private area an act writes in — a materialization of the tip the actor
/// read, which the actor owns alone and discards when it is done.
///
/// # Why the primitive owes this
///
/// **The compare-and-swap protects the ref and nothing inside a directory.**
/// Two bodies woken for one landing, writing into one shared worktree, corrupt
/// each other's payload *before* either reaches the swap — the concurrency the
/// CAS exists to catch, happening one floor below it, after which both land
/// honestly. Letting each actor choose where to write is what makes that race
/// possible, so opening the area is a first-class operation of the primitive
/// rather than a convention actors are asked to keep.
///
/// # The obligation
///
/// A workspace carries a debt: it holds a real directory and a registered
/// worktree, and Dart has no destructor. `Instance.act` is the safe path
/// precisely because the bracket discharges that debt in a `finally`; these
/// members exist for the one shape a callback cannot serve — the coreutil's
/// plumbing family, where `work`, `commit` and `release` are three separate
/// processes and no closure spans them. They are the piece with the obligation
/// attached, never a peer of the bracket.
final class Workspace {
  Workspace({
    required this.directory,
    required this.gitDir,
    required this.ref,
    required this.expectedTip,
  });

  /// The area to write in. Ordinary file IO — the application writes whatever
  /// its own schema says, and the primitive never looks.
  final Directory directory;

  final String gitDir;

  /// The instance's ref this act will land on. A transient body works in a
  /// detached area of its own and lands on the ref all the same.
  final String ref;

  /// The tip that was read when this area was opened, and the value the swap
  /// will demand the ref still holds.
  final Commit expectedTip;

  /// Closes the act: the area's content becomes a commit declared as [name],
  /// and the ref moves by compare-and-swap against [expectedTip].
  ///
  /// Returns [Landed] or [Refused]; it does not throw for a lost race, which is
  /// an ordinary outcome and not an error. Releasing is **not** implied — the
  /// plumbing family's caller may still want the directory, and the bracket
  /// releases in its own `finally`.
  ActionResult commit(String name, {Actor? actor}) =>
      throw UnimplementedError('Workspace.commit');

  /// Discards the area and deregisters the worktree. Idempotent: the coreutil's
  /// `release` may honestly run twice.
  void release() => throw UnimplementedError('Workspace.release');
}
