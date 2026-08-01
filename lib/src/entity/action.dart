import 'model/actor.dart';
import 'model/commit.dart';

/// One exercise of agency, and the irreducible act of the platform: **an actor
/// wrote into an instance's worktree and committed. The commit is the action.**
///
/// Read any log and what stands there is not commits appearing on their own but
/// *someone having done something* — the actor in the author field, the act
/// declared in the commit, the state change in the diff. Signed, attributable,
/// dated, published.
///
/// # One event, three jobs
///
/// The action is the **deliverable** — its [diff] is the payload the next
/// reader takes. It is the **activation** — the act qualified by phase is what
/// wakes whoever is armed. And it is the **state transition** — what the
/// entity's machine advances by. One event read from three sides, never three
/// mechanisms kept in agreement.
///
/// # It is named by what it deposits
///
/// There is only one verb, and it is *write*. Nothing executes the object, so
/// naming the verb was always redundancy; what an action has of its own is the
/// thing it leaves behind, and that is its [name] — a noun, singular, in the
/// application's vocabulary: `prompt`, `reply`, `tool-result`, `approval`.
/// `commit` is the floor talking about itself; `say` and `run` name the doing,
/// which is identical in every action.
///
/// This type is a **handle at (instance, sha)**: live like every handle here,
/// reading the substrate on each access rather than snapshotting it.
final class Action {
  /// Reads the action landed at [commit] of the instance's ref.
  Action({required this.gitDir, required this.ref, required this.commit});

  /// The entity's own directory — the common one. A ref update made from a
  /// worktree resolves to that worktree's private directory, where no table and
  /// no history live; that mistake fails silently, so the resolution is the
  /// primitive's and never a caller's.
  final String gitDir;

  /// The instance's ref this act landed on.
  final String ref;

  /// The action's identity: the commit is the event, so its object name is the
  /// event's name too.
  final Commit commit;

  /// The declared noun, read from the commit's structured form. The **only**
  /// part of an act the substrate reads — enough to match a subscription, never
  /// enough to interpret.
  String get name => throw UnimplementedError('Action.name');

  /// Who acted, from the commit's author.
  Actor get actor => throw UnimplementedError('Action.actor');

  /// When, from the commit's author date.
  DateTime get instant => throw UnimplementedError('Action.instant');

  /// The state the act was taken *at* — the value the swap demanded the ref
  /// still hold.
  Commit get parent => throw UnimplementedError('Action.parent');

  /// What this act changed. Derived on every call, because the substrate stores
  /// whole states and never differences.
  Diff diff() => throw UnimplementedError('Action.diff');

  /// The structured form the action's name is written in and read back from.
  ///
  /// The message's subject is the noun, and this trailer states it
  /// unambiguously for the reader that must not parse prose — chiefly the
  /// shell shim in the hook path, which matches subscriptions with no Dart
  /// anywhere. Design decision: a trailer, not the subject alone, because a
  /// subject is a human surface and a matcher must not depend on one.
  static const String nameTrailer = 'Bentos-Action';

  /// The message an act commits with, given its noun.
  static String messageFor(String name) => '$name\n\n$nameTrailer: $name\n';

  /// The declared noun carried by [message], or null when it declares none —
  /// which is what an ordinary Git commit made outside the ontology looks like,
  /// and it is never an error.
  static String? nameIn(String message) {
    for (final line in message.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('$nameTrailer:')) {
        return trimmed.substring(nameTrailer.length + 1).trim();
      }
    }
    return null;
  }
}

/// What an act returned. **Refusal is a value, not an exception**: the ref
/// moved, or a gate said no, and both are ordinary outcomes of concurrent
/// agency, answered by re-reading and retrying. Sealed, so the caller cannot
/// forget the branch.
sealed class ActionResult {
  const ActionResult();
}

/// The act became true, at [action].
final class Landed extends ActionResult {
  const Landed(this.action);
  final Action action;
}

/// The act did not become true. [reason] is what the caller can be told, and it
/// is deliberately thin: the substrate aborts a transaction whole and names no
/// culprit, so anything richer had to be said by whoever refused.
final class Refused extends ActionResult {
  const Refused(this.reason, {this.expected, this.found});

  final String reason;

  /// The tip the actor read and swapped against.
  final Commit? expected;

  /// The tip the substrate actually held, when it is known — the ordinary case
  /// being another actor that landed first.
  final Commit? found;
}
