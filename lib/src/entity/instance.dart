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

  /// Takes one action: **writes in the instance's own worktree and commits
  /// there**. The branch moves because the commit happened in it — no private
  /// area, no tree written aside, no compare-and-swap.
  ///
  /// **It commits where the instance already stands.** [standingAt] is the
  /// substrate's own answer to that, and it is asked rather than assumed: an
  /// act that materialized at the convention address regardless would stand a
  /// *second* tree beside a face somebody put at another path, commit there,
  /// and leave that face behind holding the previous state — the person who
  /// asked for the files watching them never change. Only when the instance
  /// stands nowhere is a tree stood up, at the convention address.
  ///
  /// It is attached to this instance's branch: a commit in a detached tree
  /// advances nothing anyone holds, which is why [Git.commitInWorktree]
  /// refuses one.
  ///
  /// **It refuses a tree that carries uncommitted work**, with
  /// [TreeCarriesWork]. The commit *is* the action, so its diff must be
  /// exactly what this act deposited; a tree carrying somebody's unrelated
  /// edits would put their work into the ledger under this act's name, which
  /// is silent corruption of the one thing the product is. A person who edited
  /// by hand and then acted is doing two things at once, and the refusal says
  /// so. It is thrown and never returned: nothing was attempted, and an
  /// absence is not an outcome of an act.
  ///
  /// That refusal is load-bearing twice. Because the tree was proved clean
  /// before [body] ran, **everything standing afterwards was deposited by this
  /// act** — so an act that does not land can restore the tree without
  /// destroying anyone's afternoon, and it does. Leaving the deposit standing
  /// would refuse the *next* act, for everyone, forever.
  ///
  /// **It does not invoke the entity.** Nothing executes an object whose state
  /// changes by being written to: this frames *the caller's own write*, and the
  /// declared [name] is what makes it an event anyone can arm on.
  ///
  /// Returns [Landed] or [Barred]. **[Contested] is no longer reachable from
  /// an act** — there is no swap to lose — and stays in the type because
  /// [fetch] still produces it. A [body] that throws unwinds as [ActUnwound],
  /// carrying the cause and what the restore discarded.
  ///
  /// **[actor] is required**, so an act with no stated actor is not
  /// expressible. What filled it when it could be left out was the machine's
  /// own git cascade — whoever owns the checkout, which is a different person
  /// from whoever acted.
  Future<ActionResult> act(
    String name,
    FutureOr<void> Function(Materialization) body, {
    required Actor actor,
    String? say,
  }) async {
    final gitDir = _gitDir;
    // Where it stands, or where it will: `materialize` with the standing path
    // is the idempotent branch and returns that same tree untouched, so this
    // is one call for both cases and never a second tree.
    final standingHere = standingAt;
    final area = materialize(at: standingHere.isEmpty ? null : standingHere.first);
    final path = area.directory.path;
    final standing = ambientGit.revParse(gitDir, ref)!;
    final carried = ambientGit.worktreeDirtyPaths(path);
    if (carried.isNotEmpty) throw TreeCarriesWork(path, carried);
    try {
      await body(area);
    } catch (cause) {
      // The body failed, so nothing lands — and what it wrote must not stay
      // behind to refuse the next act. Read before discarding: the paths are
      // the only account anyone gets of what this cost.
      final discarded = ambientGit.worktreeDirtyPaths(path);
      ambientGit.worktreeDiscard(path, to: standing);
      throw ActUnwound(cause, directory: path, discarded: discarded);
    }
    final outcome = ambientGit.commitInWorktree(
      path,
      message: Action.messageFor(name, say: say),
      actor: actor,
    );
    final landed = outcome.commit;
    if (landed != null) {
      return Landed(Action(gitDir: gitDir, ref: ref, commit: landed));
    }
    final discarded = ambientGit.worktreeDirtyPaths(path);
    ambientGit.worktreeDiscard(path, to: standing);
    return Barred(
      gateRefusalIn(outcome.report) ?? 'refused by a gate',
      discarded: discarded,
    );
  }

  /// Opens the private area with the obligation attached — the piece of the
  /// **old** acting path, for callers that cannot be a callback.
  ///
  /// **Retired in place, and not by this slice.** [act] no longer comes
  /// through here: it commits in the instance's own attached worktree. What is
  /// left standing is the plumbing family and the chat seam, and both come out
  /// with [Workspace] itself. Until they do, a caller that opens one of these
  /// while a materialization stands attached lands a ref move from *outside* a
  /// tree that follows it — the corruption the new path exists to remove.
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

  /// Where this instance presently stands as a materialization — zero, one, or
  /// several paths, all equally legal. Read straight from the substrate's own
  /// record of worktrees attached to this instance's branch: nothing here
  /// keeps a register of its own, so this is exactly as current as `git
  /// worktree list` is.
  List<String> get standingAt => ambientGit.worktreesOn(_gitDir, id);

  /// Where this instance's worktree stands when nobody names a path — the
  /// **convention address**, `instances/<id>` inside the installation, sibling
  /// of the class's own `genesis/`.
  ///
  /// A convention and not a temporary: an act commits in this tree, so the
  /// address is somewhere a person opens, greps and edits. What used to stand
  /// here was a freshly-named directory under `faces/` — the right shape for a
  /// tree nobody addresses, and the wrong one for the tree an instance *is*.
  String get conventionAddress =>
      p.join(p.dirname(_gitDir), instancesDirName, id);

  /// The directory instances stand in, beside the class's own stage.
  static const String instancesDirName = 'instances';

  /// Puts the instance into the materialized condition: a worktree **attached
  /// to this instance's branch**, at [at] or at the convention address.
  ///
  /// **Attached, and that is the whole of how an act lands.** A commit made in
  /// this tree moves the branch by happening; a detached tree would advance its
  /// own private `HEAD` and leave the object held by nobody. So the tree a
  /// person edits in and the tree an act commits in are one tree — which is
  /// what makes [act]'s refusal of uncommitted work necessary rather than
  /// fussy.
  ///
  /// Idempotent where the tree is already ours and already follows this
  /// instance: it is left exactly as it stands, because someone may be looking
  /// at it. A tree of ours standing **detached** there is refused rather than
  /// re-attached — it is residue of the old acting path, and re-attaching it
  /// silently would carry whatever it holds into the ledger.
  ///
  /// **One attached tree, and a second address is refused.** An instance
  /// stands in exactly one place, named by [standingAt]; asking for it at
  /// another path while it stands somewhere raises [InstanceStandsElsewhere]
  /// rather than putting a second tree on the branch. The substrate refuses
  /// that too, now that [Git.worktreeAdd] no longer overrides it — this
  /// refuses first, so the reader is told where the instance actually stands
  /// instead of reading Git's own sentence about a branch.
  ///
  /// A face somewhere else is a **detached** tree at a commit, read-only by
  /// construction: nothing it commits can move a ref, which is exactly what
  /// makes several of them free.
  Materialization materialize({String? at}) {
    final gitDir = _gitDir;
    final standing = ambientGit.revParse(gitDir, ref);
    if (standing == null) throw StateError('not born: $this');
    final path = at ?? conventionAddress;
    if (ambientGit.worktreeRepository(path) == gitDir) {
      final follows = ambientGit.currentBranch(path);
      if (follows != id) throw WorktreeUnattached(path, '$this', follows: follows);
      return materialization(path);
    }
    // Asked before the add, because the substrate's refusal names a branch and
    // a directory the caller never typed, and the question they actually asked
    // is *where does this instance stand*.
    final elsewhere = standingAt;
    if (elsewhere.isNotEmpty) {
      throw InstanceStandsElsewhere(path, '$this', standingAt: elsewhere);
    }
    ambientGit.worktreeAdd(gitDir, path: path, at: standing, branch: id);
    return materialization(path);
  }

  /// The materialization standing at [path], **mounted from the disk** — the
  /// handle for a process that did not stand the tree up and holds only a
  /// directory.
  ///
  /// The ref comes from here and not from the tree. An instance's own tree is
  /// attached and could name its branch, but a **face** — a detached tree at a
  /// commit — cannot, and this handle serves both. That is the same fact
  /// `entity refresh` takes a coordinate for.
  Materialization materialization(String path) => Materialization(
        directory: Directory(path),
        gitDir: _gitDir,
        ref: ref,
        attachAddress: conventionAddress,
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

/// [Instance.act] was asked to act in a worktree that already carries
/// uncommitted work.
///
/// **Not an [ActionResult]**: nothing was attempted, no gate was asked and no
/// ref moved, so this is an absence rather than an outcome — and an absence
/// never travels as a value in that type.
///
/// The commit *is* the action, so its diff must be exactly what the act
/// deposited. A tree carrying somebody's unrelated edits would land their work
/// in the ledger under this act's name. Whoever hit this is doing two things
/// at once, and the cure is theirs to choose: commit what they wrote, or put
/// it aside.
final class TreeCarriesWork implements Exception {
  const TreeCarriesWork(this.directory, this.paths);

  /// The worktree the act would have committed in.
  final String directory;

  /// What stands there: modified, staged and untracked alike.
  final List<String> paths;

  @override
  String toString() => [
        'the tree at $directory carries uncommitted work, '
            'and an act commits the whole of it',
        ...paths.map((path) => '  $path'),
        '  commit it or set it aside first: git -C $directory status',
      ].join('\n');
}

/// A worktree stands at the address an act would use, and it does **not**
/// follow the instance — the residue of the old acting path, or a tree
/// somebody detached by hand.
///
/// Refused rather than re-attached: whatever it holds would be carried into
/// the ledger by the first act that came through, and the tree belongs to
/// whoever stood it up.
final class WorktreeUnattached implements Exception {
  const WorktreeUnattached(this.directory, this.instance, {this.follows});

  final String directory;

  /// The instance the tree was expected to follow.
  final String instance;

  /// What it follows instead, or null when it stands detached.
  final String? follows;

  @override
  String toString() => [
        'the tree at $directory does not follow $instance '
            '(${follows == null ? 'detached' : "follows '$follows'"})',
        '  an act commits in the instance\'s own tree, and a tree that follows '
            'something else would land its content under this act',
        '  release it or attach it at the line: git -C $directory status',
      ].join('\n');
}

/// A second address was asked for an instance that already stands somewhere.
///
/// **One attached tree per instance.** Two trees following one branch leave
/// each other behind the moment either commits, and the lagging one carries
/// its stale index into the ledger: the sibling's files leave the branch while
/// still standing on the sibling's disk. Git refuses the second tree on its
/// own; this refuses first, so the sentence names where the instance stands
/// rather than which branch was already checked out.
///
/// A face at another path is a detached worktree at a commit — read-only, and
/// as many as anyone wants.
final class InstanceStandsElsewhere implements Exception {
  const InstanceStandsElsewhere(this.asked, this.instance,
      {required this.standingAt});

  /// The path the caller asked for.
  final String asked;

  final String instance;

  /// Where the instance presently stands — the substrate's own answer.
  final List<String> standingAt;

  @override
  String toString() => [
        '$instance already stands at ${standingAt.join(', ')}, '
            'and cannot also stand at $asked',
        '  one attached tree per instance: a second would fall behind the '
            'first, and a commit taken in it would drop the first tree\'s '
            'files from the line',
        '  read it where it stands, or release it first',
      ].join('\n');
}

/// An act's [body] threw, so nothing landed — and what the body had already
/// written was discarded to put the tree back where it stood.
///
/// **The cause travels whole**, because it is the caller's own error and the
/// only thing that explains the failure; what this adds is the account of the
/// destruction, which nobody else can give.
final class ActUnwound implements Exception {
  const ActUnwound(this.cause, {required this.directory, required this.discarded});

  /// What the body threw.
  final Object cause;

  /// The tree that was restored.
  final String directory;

  /// The paths the restore destroyed — the act's own deposit, guaranteed by
  /// the clean-tree refusal that ran before the body did.
  final List<String> discarded;

  @override
  String toString() => 'the act unwound and its tree was restored: $cause';
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
