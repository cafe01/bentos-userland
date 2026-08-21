import 'model/actor.dart';
import 'model/commit.dart';
import 'model/remote.dart';

/// One commit as the substrate reports it — the raw record the ontology dresses
/// as an [Action].
final class RawCommit {
  const RawCommit({
    required this.sha,
    required this.parents,
    required this.author,
    required this.instant,
    required this.message,
  });

  final String sha;
  final List<String> parents;
  /// Who the commit says wrote it. A read model — a record written before the
  /// identity was mandatory carries whatever it carried, and reporting that is
  /// not the same act as signing under it.
  final Attribution author;
  final DateTime instant;

  /// The commit message entire — subject line and trailers. What the ontology
  /// reads out of it is the declared action name, and nothing else.
  final String message;
}

/// The outcome of a compare-and-swap: whether the ref moved, and what the
/// substrate said when it did not.
///
/// **A bool discards the evidence.** Git distinguishes a lost race from a gate's
/// refusal in its own words — `cannot lock ref … reference already exists`
/// against `ref updates aborted by hook`, the hook's own stderr above it — and a
/// port that answers `false` to both forces the floor above to guess. It guessed
/// by re-reading the ref, which is how a refusal by a gate came to print
/// `expected b71043a, found b71043a`.
///
/// Classification stays **above** the port: what travels here is the substrate's
/// report, unread.
final class RefUpdate {
  const RefUpdate({required this.moved, this.report = ''});

  /// True when the ref now holds the new value.
  final bool moved;

  /// What the substrate wrote while refusing, verbatim and undecoded of meaning.
  /// Empty when the ref moved.
  final String report;
}

/// The outcome of an unforced worktree checkout: whether the tree now stands
/// at the requested commit, and what the substrate said when it declined.
///
/// **Mirrors [RefUpdate] for the same reason.** A worktree carrying edits the
/// checkout would overwrite is Git refusing an ordinary request, not the
/// command failing to run — so this travels back as a value the caller reads,
/// never as a thrown fault. Classification stays above the port: what
/// travels here is the substrate's report, unread.
final class WorktreeCheckout {
  const WorktreeCheckout({required this.moved, this.report = ''});

  /// True when the worktree now stands at the requested commit.
  final bool moved;

  /// What the substrate wrote while declining, verbatim and undecoded of
  /// meaning. Empty when the worktree moved.
  final String report;
}

/// The Git port — **the one abstract type in the entity package**.
///
/// The entity *is* a Git repository and there will be no second implementation
/// of the entity; what varies is the substrate underneath it, so the substrate
/// is what carries the abstraction. Every other type here is a `final class`,
/// because abstracting them would be inventing a choice nobody has.
///
/// # Why a port exists at all
///
/// Git is a subprocess, and `IOOverrides` does not reach subprocesses — so the
/// hermeticity `Place` gets free from the platform must be authored here. This
/// is the seam that buys it.
///
/// # Where the cut is
///
/// **At the plumbing verb.** Cut lower — at argv — and a test asserts command
/// lines, which is testing the implementation rather than the behaviour. Not
/// cut at all, and every unit test needs a real repository on disk.
///
/// This is also **the one place the ontology may speak Git's dialect**: refs,
/// trees, objects, worktrees. The port *is* the first storey, and above it the
/// names are ours — an [Instance] is never called a branch, an [Action] never a
/// commit.
///
/// # The sync/async law
///
/// > Synchronous is what costs local disk and our own code. Asynchronous is
/// > what crosses the network or runs a body that is not ours.
///
/// Reads of refs, objects and trees are synchronous, which is what keeps the
/// hook and reactor paths plain. [clone], [push] and [fetch] cross the network
/// and are the only asynchronous members. The divergence from `Place` is
/// declared rather than disguised: here *local* means a process spawn of some
/// milliseconds, not a stat — a cost accepted in line, not a cost pretended
/// away.
///
/// # Injection
///
/// Never a constructor argument. The port is a zone-scoped ambient (see
/// `git_ambient.dart`), exactly as `Place`'s home is and for the same reason: a
/// subprocess is an ambient fact of the same kind. `Entity(name)` therefore
/// stays a bare handle, and no god-object threads a collaborator through the
/// graph.
///
/// A test double is scoped to these verbs and nothing more. **A double that
/// grows past them has reimplemented Git**, and its green is worth nothing.
abstract interface class Git {
  /// Creates a repository at [gitDir]. Entities are **bare**: an instance is a
  /// ref and its state is a worktree, so a default checkout at the root would
  /// lie about which of the two it is.
  void init(String gitDir, {bool bare = true});

  /// Writes [bytes] as a loose object and returns its name.
  String hashObject(String gitDir, List<int> bytes);

  /// The bytes of [object] — a sha, or a `<rev>:<path>` selector, which is how
  /// content is read at a ref with no worktree anywhere.
  List<int> catFile(String gitDir, String object);

  /// The entry names directly under [path] in the tree at [at] — full paths
  /// from the root, sorted, one level deep, and empty where nothing is there.
  ///
  /// The listing half of reading at a ref. [catFile] hands back one path at a
  /// time, so without this every reader of composite state has to leave the
  /// ontology to find out what the paths *are*.
  List<String> lsTree(String gitDir, {required Commit at, required String path});

  /// Whether [ancestor] is reachable from [descendant] — the question that
  /// separates a line extended from two lines diverged, and the only thing
  /// [fetch]'s caller needs in order to know which of the two it received.
  bool isAncestor(
    String gitDir, {
    required Commit ancestor,
    required Commit descendant,
  });

  /// Stages [workTree] entire and writes its tree object, returning the name.
  /// The staging is folded in deliberately: *the tree of this worktree* is one
  /// idea, and splitting it would put an index — a detail of the substrate —
  /// into the ontology's hands.
  String writeTree(String gitDir, {required String workTree});

  /// Writes a commit object over [tree]. The object exists on disk the moment
  /// this returns, which is why a refusal one step later cannot rewrite it:
  /// the payload is hashed before any listener sees it.
  String commitTree(
    String gitDir, {
    required String tree,
    required List<String> parents,
    required String message,
    required Actor actor,
  });

  /// The compare-and-swap, and the reason the last step of an action is
  /// plumbing: [expected] is the value the ref must still hold, and the
  /// substrate either moves it under lock or refuses.
  ///
  /// Returns a [RefUpdate]: the ref moved, or it did not and the substrate's
  /// own account of why travels back with the answer — refusal is an **ordinary
  /// outcome of concurrent agency**, not an error. A `null` [expected] means
  /// *the ref must not exist*.
  ///
  /// This is also the emission point of every event: the armed shim rides the
  /// `reference-transaction` hook, so a refusal here fires `.refused` and a
  /// success fires `.landed`, locally and on the receiving side of a push
  /// alike.
  RefUpdate updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  });

  /// Points a new ref at [startPoint] — the birth of an instance, whether from
  /// genesis or, identically, as a fork from a live commit.
  void branch(String gitDir, {required String name, required Commit startPoint});

  /// The ref names under `refs/heads/`, unqualified.
  List<String> branches(String gitDir);

  /// The commit a ref points at, or null when the ref does not exist.
  Commit? revParse(String gitDir, String rev);

  /// The commits reachable from [ref] but not from any of [excluding], newest
  /// first — the incremental path: a caller already holding a commit it has
  /// seen names it here and pays only for what lies beyond it, since a
  /// first-parent walk stops descending the moment it meets ground the
  /// exclusion already covers.
  List<RawCommit> log(
    String gitDir, {
    required String ref,
    int? limit,
    List<String> excluding = const [],
  });

  /// One commit's record.
  RawCommit showCommit(String gitDir, Commit commit);

  /// What changed between two commits — always derived, never stored.
  Diff diffTree(String gitDir, {required Commit from, required Commit to});

  /// Checks [ref] out at [path] as a worktree of this repository. The object
  /// store is shared, so the history is stored once however many worktrees
  /// stand at once; only the files are copied.
  ///
  /// **Detached by default** — [at] alone, no ref anyone can move underfoot —
  /// which is what a private area and a class stage both need: nothing but
  /// this call may ever advance what they stand on. Pass [branch] and the
  /// worktree stands **attached** to it instead: `HEAD` a symref, so an
  /// ordinary commit taken inside moves the branch and the tree together, in
  /// the one motion Git already means by "checked out". [at] is still the
  /// commit the caller believes the branch presently holds; the argument
  /// travelling to Git is the branch's name, and Git resolves its own tip.
  ///
  /// Zero, one, or several worktrees may stand attached to the same branch at
  /// once — Git's own default refuses a second, and every call here overrides
  /// that safeguard on purpose, because several standing at once is a legal
  /// shape here, not an accident to be caught. What follows from allowing it
  /// is on the caller: a branch two attached trees both watch can leave either
  /// one behind the other, and nothing at this port catches that up for free.
  void worktreeAdd(
    String gitDir, {
    required String path,
    required Commit at,
    String? branch,
  });

  /// The linked worktrees of [gitDir] presently attached to [branch] — the
  /// substrate's own record of where an instance stands, since nothing above
  /// this port keeps a register of its own. Zero, one, or several, all
  /// equally legal; sorted, so a caller reading one deterministically may.
  List<String> worktreesOn(String gitDir, String branch);

  /// Discards the worktree at [path] and deregisters it. Leaving it registered
  /// is the leak the API exists to prevent.
  ///
  /// **This verb deletes a directory, so possession is checked before it acts**:
  /// [path] must stand among the linked worktrees this repository has
  /// registered, or [WorktreeNotOurs] is raised and nothing is touched. The
  /// substrate's refusal is the last word — a directory Git declined to remove
  /// is never removed by us afterwards.
  void worktreeRemove(String gitDir, {required String path});

  /// Moves the worktree at [path] to [to] — an **unforced** `git checkout`.
  ///
  /// Git's own reason to decline is a tree still carrying local changes the
  /// move would overwrite, and this member does exactly what plain
  /// `checkout` does: asks, and accepts the answer. Never `--force`, never a
  /// stash, never a clean — content Git declines to touch is content this
  /// leaves standing. [worktreeRemove]'s forced discard is a different verb
  /// for a different caller: releasing a tree nobody is reading from any
  /// longer, not catching one up.
  ///
  /// Returns a [WorktreeCheckout]: moved, or refused with the substrate's own
  /// account of why. A fault that is not the ordinary refusal — [path] no
  /// worktree at all, [to] no object this repository holds — still throws:
  /// only the dirty-tree refusal is a decided outcome.
  WorktreeCheckout worktreeCheckout(String path, {required Commit to});

  /// The paths that carry a person's uncommitted work in the worktree at
  /// [path] — tracked and modified, staged, or untracked alike. `git status
  /// --porcelain`, underneath, with nothing decided about what the paths
  /// mean: that judgment belongs to whoever asked, one storey up. Empty
  /// means clean, never a special case a caller must test for separately.
  ///
  /// Asked from inside the worktree, exactly as [worktreeCheckout] is and
  /// for the same reason: a linked worktree's status is a fact about the
  /// tree standing at [path], not about the repository by name.
  List<String> worktreeDirtyPaths(String path);

  /// The repository a standing worktree belongs to — its **common** directory,
  /// never the private one a worktree also has.
  ///
  /// The one resolution that runs the other way round: everywhere else the
  /// primitive holds the repository and names a path, and here a path is all a
  /// caller has. `entity release <path>` is why it exists — a workspace and a
  /// materialization are handed to the shell as directories, and three separate
  /// processes cannot pass a handle between them.
  ///
  /// **Possession, never vicinity.** Every directory inside a repository can
  /// name that repository, and a linked worktree of ours is a different fact
  /// entirely: this answers only for the second. A repository's own main
  /// working tree is not one of ours either — it is precisely the directory a
  /// wrong path is likeliest to name, and it belongs to whoever works there.
  ///
  /// Null when [path] is no linked worktree, which is the ordinary answer for a
  /// caller that released twice and the honest one for somebody else's disk.
  String? worktreeRepository(String path);

  /// The commit the worktree at [path] stands at — the other half of the
  /// backwards resolution, and the fact a materialization is otherwise unable
  /// to report about itself in a process that did not create it.
  ///
  /// **A fact about the files only while the tree stands detached** — which a
  /// worktree of ours is meant to, and which nothing here enforces. Where
  /// `HEAD` is a symref this answers through the ref instead, so a caller that
  /// wants where the *looker* stands must establish detachment first
  /// ([currentBranch]) rather than assume it. This member reports `HEAD`; it
  /// does not decide what `HEAD` was pointing at.
  ///
  /// Null when [path] is no worktree, exactly as [worktreeRepository] is.
  Commit? worktreeHead(String path);

  // -------------------------------------------------------- the superproject

  /// The working tree root of the repository containing [path], or null when
  /// nothing there is one.
  ///
  /// The superproject's half of the model asks the question the other way round
  /// from everything above: a place is handed to us as a directory and whether
  /// it lies inside a repository — and which — is the substrate's to answer.
  String? topLevel(String path);

  /// The branch checked out in [workTree], or null when the head is detached.
  ///
  /// Asked by working tree and not by git dir, because the caller here holds a
  /// directory and no repository of its own: a place is contained by a
  /// repository, it does not own one.
  String? currentBranch(String workTree);

  /// The branch names of the repository containing [workTree].
  List<String> branchesIn(String workTree);

  /// Writes a **gitlink** into the index of the repository whose working tree
  /// is [workTree]: a tree entry of mode `160000` at [path], carrying [at].
  ///
  /// The pin is this entry and nothing else. It is an index write and stops
  /// there: the index is written by whoever registers, and the tree is written
  /// by whoever commits — so a pin is **visible and not yet true**, which is the
  /// same distinction the sister draws between `.attempted` and `.landed`. The
  /// two halves of the model reached that shape independently.
  ///
  /// [at] need not be an object this repository holds. A gitlink names a commit
  /// of *another* repository, so the superproject records the name without ever
  /// being able to resolve it — which is what makes a pinned clone cheap.
  void stageGitlink(String workTree, {required String path, required Commit at});

  /// The commit a gitlink at [path] carries, read back from the index — null
  /// when nothing is staged there, and null when what is staged is not mode
  /// `160000`, because an ordinary file at that path is not a weaker pin but a
  /// different thing entirely.
  Commit? stagedGitlink(String workTree, String path);

  /// Removes the index entry at [path] — `git update-index --force-remove`.
  ///
  /// The pin's undo, and the reason it exists is symmetry rather than
  /// convenience: a registration that can be written and not withdrawn cannot
  /// be rolled back, and a constructor that cannot roll back leaves half an
  /// installation behind every time it throws.
  ///
  /// Silent where nothing is staged there: removing what is not there is the
  /// state the caller asked for.
  void unstageGitlink(String workTree, String path);

  /// Every index entry at or under [path], mode included — `git ls-files
  /// --stage`, unfiltered.
  ///
  /// [stagedGitlink] answers *is the pin here*; this answers *what else is*,
  /// and the difference is the whole of a legible refusal. `update-index
  /// --cacheinfo 160000` fails when ordinary blobs are already tracked under
  /// the path, and the caller that asked only about a gitlink saw `null` — an
  /// absence indistinguishable from empty ground — and walked into git's own
  /// sentence about a file it never mentioned.
  ///
  /// Returns the entries as the index holds them, mode unparsed: whether mode
  /// `100644` under an installation's path is a fault is the caller's question
  /// and not the port's.
  List<({String mode, String sha, String path})> stagedEntries(
    String workTree,
    String path,
  );

  /// The declared remotes.
  List<Remote> remotes(String gitDir);

  /// Declares a remote. Declaring is not electing: which copy is authoritative
  /// is said elsewhere, and this only records where bytes may travel.
  void addRemote(String gitDir, {required String name, required String url});

  /// Repoints an **already declared** remote at [url] — `git remote set-url`.
  ///
  /// Not [addRemote] with a different argument, and the distinction is
  /// load-bearing rather than stylistic: `git remote add` writes git's default
  /// fetch refspec, `set-url` writes nothing but the URL. An installation's
  /// origin is refspec-free by construction, and that premise is what makes a
  /// named fetch fill `FETCH_HEAD` and write no ref at all. Reaching for
  /// [addRemote] here — the obvious later simplification, since it would also
  /// leave the URL right — silently acquires a refspec and takes the premise
  /// with it.
  ///
  /// Throws where [name] is not declared. The caller knows whether it is.
  void setRemoteUrl(String gitDir, {required String name, required String url});

  /// Copies a repository from [source] into [gitDir]. Crosses the network.
  Future<void> clone(String source, String gitDir, {bool bare = true});

  /// Sends refs to [remote]. The receiving side runs its own hook and may
  /// refuse, which is federation using exactly the mechanism local action uses.
  Future<void> push(String gitDir, {required String remote, String? ref});

  /// Brings [ref] down from [remote] and answers **what arrived**: the commit
  /// the remote's line stands at, or null when the remote has no such ref.
  ///
  /// Nothing is merged and no local ref moves — what arrives is another
  /// participant's line, and what to do about it is the ontology's word one
  /// floor up. The return value is what makes that possible: a line brought
  /// down and left unnamed is a state nothing above here can speak of.
  Future<Commit?> fetch(
    String gitDir, {
    required String remote,
    required String ref,
  });
}

/// A worktree verb was aimed at a path the repository does not hold as a linked
/// worktree of its own — an ordinary directory, a foreign repository's tree, a
/// repository's own main working tree.
///
/// It exists because the verb that raises it **deletes disk**. Every other
/// mistake in this port costs an error message; this one costs whatever stood
/// there, so the fault is a type a caller can catch rather than a silent
/// success, and no path arrives at the deletion without having been claimed.
final class WorktreeNotOurs implements Exception {
  const WorktreeNotOurs(this.path, {this.repository});

  final String path;

  /// The repository asked, when there was one to ask.
  final String? repository;

  @override
  String toString() => 'not a worktree of ours: $path'
      '${repository == null ? '' : ' (asked of $repository)'}';
}
