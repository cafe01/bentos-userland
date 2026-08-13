import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'action.dart';
import 'entity.dart';
import 'event.dart';
import '../git/git_ambient.dart';
import 'materialization.dart';
import '../git/model/actor.dart';
import '../git/model/commit.dart';
import '../place/place.dart';
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
  ///
  /// **The birth is a compare-and-swap**, at the same ref and through the same
  /// verb every act lands by: [Git.updateRef] with no expectation, which is the
  /// substrate's own way of saying *this ref must not exist*. It used to be
  /// `git branch`, which reads and creates in one command that has no way to
  /// report a lost race — the second writer through the gap got a raw
  /// `cannot lock ref` thrown at it, out of a surface whose whole promise is
  /// that concurrent agency is a value. What is deliberate here stays
  /// deliberate: a name already taken raises [InstanceExists], because a caller
  /// that typed `entity new` asked to *make* one and did not.
  Instance create({Commit? from}) {
    if (!_birth(from: from)) throw InstanceExists(entity.name, id);
    return this;
  }

  /// Births it if nobody has — **idempotent**, and the verb for a caller whose
  /// need is *the instance exists* rather than *I made it*. Answers whether
  /// this call was the one that birthed it.
  ///
  /// The distinction matters exactly where several actors arrive at once, which
  /// is ordinary for anything an external will enters through: a channel that
  /// four beings join at the same instant is born once, and the three that lost
  /// find it born rather than broken. Losing that race and never having run it
  /// are the same world, so they are the same answer.
  bool ensureBorn({Commit? from}) => tip != null ? false : _birth(from: from);

  /// The swap itself: the ref moves from nothing to [from], or somebody else
  /// moved it first. No read precedes it — a read would only widen the gap the
  /// swap exists to close.
  bool _birth({Commit? from}) => ambientGit
      .updateRef(
        _gitDir,
        ref: ref,
        newCommit: from ?? entity.genesis,
        expected: null,
      )
      .moved;

  /// The acts of this instance, newest first. Reading an instance's events in
  /// sequence *is* reading its log under another name, which is why an actor's
  /// context comes free with the medium.
  ///
  /// With [since], only the acts **after** it — a caller that has already read
  /// up to a commit it holds pays for the delta and not for the whole history:
  /// the walk is `ref`'s first-parent chain, and it stops descending the
  /// instant it meets [since] rather than continuing to genesis. [since] need
  /// not be this instance's own act; any commit on its first-parent chain
  /// works, which is what makes a fork's inherited past a legal cursor too.
  ///
  /// The walk always also stops at genesis: the structure an instance was born
  /// from is not one of its acts, which is why birthing leaves no action
  /// behind. Genesis may itself have been advanced more than once — an entity
  /// re-authored after instances already forked from it — so what is excluded
  /// is every commit reachable from genesis's own tip, never only the single
  /// sha it presently names. Excluding it stays in force even with [since]:
  /// nothing guarantees the cursor postdates the latest genesis advance.
  List<Action> log({Commit? since}) {
    final gitDir = _gitDir;
    final at = ambientGit.revParse(gitDir, ref);
    if (at == null) return const [];
    return [
      for (final record in ambientGit.log(
        gitDir,
        ref: ref,
        excluding: [Entity.genesisRef, if (since != null) since.sha],
      ))
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
  /// releases the area in a `finally`. [say] rides along as the act's legible
  /// sentence, stored and never interpreted.
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
  ///
  /// **[actor] is required**, so an act with no stated actor is not
  /// expressible. The concept was always here — what was wrong is that it could
  /// be left out, and what filled it then was the machine's own git cascade.
  Future<ActionResult> act(
    String name,
    FutureOr<void> Function(Workspace) body, {
    required Actor actor,
    String? say,
  }) async {
    final workspace = beginAct();
    try {
      await body(workspace);
      return workspace.commit(name, actor: actor, say: say);
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
    final area = _privateArea(gitDir, 'acts', 'act-');
    area.deleteSync();
    ambientGit.worktreeAdd(gitDir, path: area.path, at: at);
    return Workspace(
      directory: Directory(area.path),
      gitDir: gitDir,
      ref: ref,
      expectedTip: at,
    );
  }

  /// Runs the entity's declared [function] with the context already laid —
  /// **not `invoke`**: nothing here validates a noun, honours a deposit, or
  /// reads an `on:` row. What this resolves is the file the manifest names,
  /// and what it does with it is exec and nothing else. The instance travels
  /// **verbatim** in `BENTOS_INSTANCE` — never looked up, never required to
  /// be born, since a function that needs it to exist finds that out itself.
  ///
  /// Transparent, not replaced: this stays the child's parent and inherits
  /// all three streams, stdin included — a body that reads must not hang.
  /// The child's exit code rides back on [ProcessResult.exitCode], unedited.
  ///
  /// Refuses by throwing — [FunctionNotDeclared], [FunctionNotExecutable],
  /// [ClassNotStaged], [ClassStale] — carrying the facts a caller formats a
  /// cure from, never the sentence itself: only whoever knows this
  /// installation's place can spell one.
  Future<ProcessResult> run(String function, {List<String> args = const []}) async {
    final declared = entity.manifest;
    if (!declared.functions.containsKey(function)) {
      throw FunctionNotDeclared(entity.name, function);
    }
    final exec = declared.functions[function];
    if (exec == null) {
      throw FunctionNotExecutable(entity.name, function);
    }

    final staged = entity.stagedClass;
    final standing = staged.at;
    final holds = entity.genesis;
    if (standing == null) {
      final blocked =
          staged.directory.existsSync() && staged.directory.listSync().isNotEmpty;
      throw ClassNotStaged(entity.name, staged.directory, blocked: blocked);
    }
    if (standing != holds) {
      throw ClassStale(entity.name, standing: standing, holds: holds);
    }

    final program = p.join(staged.directory.path, exec);
    final Process child;
    try {
      child = await Process.start(
        program,
        args,
        environment: {
          OccurrenceEnvironment.place: Place(p.dirname(_gitDir)).root.path,
          OccurrenceEnvironment.entity: entity.name,
          OccurrenceEnvironment.instance: id,
          OccurrenceEnvironment.coordinate: '${entity.name}:$id',
        },
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (e) {
      throw ExecutableUnavailable(
        entity.name,
        function: function,
        exec: exec,
        stagedAt: staged.directory,
        message: e.message,
      );
    }
    final code = await child.exitCode;
    return ProcessResult(child.pid, code, '', '');
  }

  /// Puts the instance into the materialized condition: a persistent worktree
  /// someone looks at. Not how an act writes — an act takes its own private
  /// area — and not something an instance needs in order to exist.
  Materialization materialize({String? at}) {
    final gitDir = _gitDir;
    final standing = ambientGit.revParse(gitDir, ref);
    if (standing == null) throw StateError('not born: $this');
    final path = at ?? (_privateArea(gitDir, 'faces', 'face-')..deleteSync()).path;
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
  /// genuinely diverged are [Diverged], and never [Contested]: the fetch
  /// succeeded and the histories disagree, so retrying changes nothing and
  /// joining them is an act of its own — divergence is legitimate rather than a
  /// fault to repair.
  ///
  /// A remote that carries no such instance is **not** a refusal and does not
  /// come back as an [ActionResult] at all: nothing declined it and nothing
  /// raced it, the thing named is simply not there. It raises
  /// [InstanceNotAtRemote], which the coreutil answers as not-found.
  Future<ActionResult> fetch(String remote) async {
    final gitDir = _gitDir;
    final standing = ambientGit.revParse(gitDir, ref);
    final arrived = await ambientGit.fetch(gitDir, remote: remote, ref: ref);
    if (arrived == null) {
      throw InstanceNotAtRemote(id, remote);
    }
    if (standing != null) {
      if (standing == arrived) {
        // Already holding it. Idempotent on purpose: fetching twice is the
        // ordinary shape of a face that polls, and the second one is not a
        // refusal.
        return Landed(Action(gitDir: gitDir, ref: ref, commit: arrived));
      }
      if (!ambientGit.isAncestor(gitDir, ancestor: standing, descendant: arrived)) {
        return Diverged(local: standing, remote: arrived);
      }
    }
    final swap = ambientGit.updateRef(
      gitDir,
      ref: ref,
      newCommit: arrived,
      expected: standing,
    );
    if (!swap.moved) {
      return Contested(
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

/// A remote carries no such instance. **Not an [ActionResult]**: no gate was
/// asked and no ref moved under anyone, so calling it a refusal would grade the
/// easy condition and flatten back together exactly what [Contested] and
/// [Barred] exist to hold apart. An absence is not an outcome of an act, and it
/// travels as this rather than as a value.
///
/// How a remote is *named* is a separate question and still open; this only
/// fixes what happens when the one named holds nothing.
final class InstanceNotAtRemote implements Exception {
  const InstanceNotAtRemote(this.instance, this.remote);

  /// The instance id the caller asked for.
  final String instance;

  /// The remote as the caller named it.
  final String remote;

  @override
  String toString() => 'no such instance $instance at $remote';
}

/// [Instance.create] was asked to birth a name that is already an instance —
/// either it was born long ago, or another actor birthed it in the instant
/// between this caller deciding to and swapping the ref.
///
/// **Deliberate birth alone raises it.** A caller that merely needs the
/// instance to exist asks [Instance.ensureBorn], for which losing that race is
/// success. Retrying changes nothing here: the name is taken, and the ref this
/// would have moved is somebody else's line now.
final class InstanceExists implements Exception {
  const InstanceExists(this.entity, this.instance);

  final String entity;

  /// The instance id the caller asked to birth.
  final String instance;

  @override
  String toString() => '$entity:$instance already exists';
}

/// [Instance.run] was asked for a function [entity]'s manifest does not
/// declare at all.
final class FunctionNotDeclared implements Exception {
  const FunctionNotDeclared(this.entity, this.function);

  final String entity;
  final String function;

  @override
  String toString() => "$entity declares no function '$function'";
}

/// [Instance.run] was asked for a function the manifest declares with no
/// executable — a declaration with nothing to exec.
final class FunctionNotExecutable implements Exception {
  const FunctionNotExecutable(this.entity, this.function);

  final String entity;
  final String function;

  @override
  String toString() => "$entity declares '$function' with no executable";
}

/// [Instance.run] found no class tree standing at [directory] — the
/// executables the manifest declares are not on disk. [blocked] is whether
/// something other than this installation's own stage already occupies the
/// directory, which changes the cure from *stand it up* to *move it aside
/// first*.
final class ClassNotStaged implements Exception {
  const ClassNotStaged(this.entity, this.directory, {required this.blocked});

  final String entity;
  final Directory directory;
  final bool blocked;

  @override
  String toString() => '$entity has no class tree at ${directory.path}';
}

/// [Instance.run] found the class tree staged, but not at the commit this
/// installation's genesis presently holds — running it would execute bodies
/// this place does not declare.
final class ClassStale implements Exception {
  const ClassStale(this.entity, {required this.standing, required this.holds});

  final String entity;
  final Commit standing;
  final Commit holds;

  @override
  String toString() =>
      '$entity stands at ${standing.short} and this installation holds ${holds.short}';
}

/// [Instance.run] resolved the function and found the class tree current, but
/// starting the executable itself failed — the rare case where the manifest
/// and the staged commit agree and the disk still does not.
final class ExecutableUnavailable implements Exception {
  const ExecutableUnavailable(
    this.entity, {
    required this.function,
    required this.exec,
    required this.stagedAt,
    required this.message,
  });

  final String entity;
  final String function;
  final String exec;
  final Directory stagedAt;
  final String message;

  @override
  String toString() => "cannot run '$function': $message";
}

/// A private directory of this installation's own, under [kind], freshly named.
///
/// **The ground an act stands on belongs to the place that holds the entity**,
/// not to the machine: the installation's slice of the plot is where a thing
/// nobody addressed can exist without being anywhere. The system's temp made a
/// global namespace out of a local fact, and put the area outside the ontology
/// entirely — invisible to the place that owns the entity it is writing into.
///
/// The slice is the repository's own parent, so resolution has already decided
/// *which* place: the walk up that answered with this [gitDir] is the same walk
/// that says where the act happens. Nothing here reaches for a `Place`.
Directory _privateArea(String gitDir, String kind, String prefix) {
  final ground = Directory(p.join(p.dirname(gitDir), kind))
    ..createSync(recursive: true);
  return ground.createTempSync(prefix);
}
