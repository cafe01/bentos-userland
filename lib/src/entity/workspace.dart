import 'dart:io';

import 'action.dart';
import '../git/git_ambient.dart';
import '../git/model/actor.dart';
import '../git/model/commit.dart';

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
  /// [say] is the legible sentence — what a person reads, stored beside the
  /// noun and never interpreted here or anywhere beneath.
  ///
  /// Returns [Landed], [Contested] or [Barred]; it does not throw for a lost
  /// race, which is
  /// an ordinary outcome and not an error. Releasing is **not** implied — the
  /// plumbing family's caller may still want the directory, and the bracket
  /// releases in its own `finally`.
  /// [actor] is **required**, and absence is caught where the caller is written
  /// rather than where the commit lands: no configuration of the machine may
  /// fill the field, so there is no shape of this call that leaves it open.
  ActionResult commit(String name, {required Actor actor, String? say}) {
    // The payload is hashed before the ref is in question — which is why a
    // refusal one step later cannot rewrite it, and why the object of a refused
    // act still exists, orphaned.
    final tree = ambientGit.writeTree(gitDir, workTree: directory.path);
    final sha = ambientGit.commitTree(
      gitDir,
      tree: tree,
      parents: [expectedTip.sha],
      message: Action.messageFor(name, say: say),
      actor: actor,
    );
    final swap = ambientGit.updateRef(
      gitDir,
      ref: ref,
      newCommit: Commit(sha),
      expected: expectedTip,
    );
    if (swap.moved) {
      return Landed(Action(gitDir: gitDir, ref: ref, commit: Commit(sha)));
    }
    // **Two refusals, and only one of them is about the ref.** A gate at
    // `attempted` refuses an act the ref never left; reporting that as a lost
    // race sends the reader to compare two values that are equal, and printing
    // `expected b71043a, found b71043a` is what a guess looks like when it is
    // wrong. The substrate said which it was; this reads it and re-reads the
    // ref only where the answer is genuinely about the ref.
    final declined = _gateRefusal(swap.report);
    if (declined != null) return Barred(declined);
    return Contested(
      expected: expectedTip,
      found: ambientGit.revParse(gitDir, ref),
    );
  }

  /// Discards the area and deregisters the worktree. Idempotent: the coreutil's
  /// `release` may honestly run twice.
  void release() => ambientGit.worktreeRemove(gitDir, path: directory.path);
}

/// The reason a gate gave, or null when the swap was refused by the ref itself.
///
/// Git's own line is the discriminator and the gate's words are what a person
/// needs: the shim names the registration that refused, and beneath it stands
/// whatever the refusing body wrote. Git's `fatal:` is dropped — it says *a
/// hook*, which the sentence already says better.
String? _gateRefusal(String report) {
  if (!report.contains(_abortedByHook)) return null;
  final words = report
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.contains(_abortedByHook))
      // Our own marker, and only ours: the shim writes `entity:` because it is
      // speaking into Git's stream where nothing else would name the program.
      // Here the program is already named by whoever prints this, and carrying
      // it through reads `entity: refused — entity: refused by r4`.
      .map((line) => line.startsWith(_ourMarker)
          ? line.substring(_ourMarker.length).trim()
          : line)
      .toList();
  if (words.isEmpty) return 'refused by a gate';
  return words.join('\n  ');
}

/// What Git writes when a `reference-transaction` hook exits non-zero at
/// `prepared`. A string, because it is the substrate's own report and there is
/// nothing else to read it by.
const String _abortedByHook = 'aborted by hook';

/// How the shim names itself when it writes into Git's stream.
const String _ourMarker = 'entity:';
