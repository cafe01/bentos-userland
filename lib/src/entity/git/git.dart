import '../model/actor.dart';
import '../model/commit.dart';
import '../model/remote.dart';

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
  final Actor author;
  final DateTime instant;

  /// The commit message entire — subject line and trailers. What the ontology
  /// reads out of it is the declared action name, and nothing else.
  final String message;
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
    Actor? actor,
  });

  /// The compare-and-swap, and the reason the last step of an action is
  /// plumbing: [expected] is the value the ref must still hold, and the
  /// substrate either moves it under lock or refuses.
  ///
  /// Returns `true` when the ref moved and `false` when it did not — refusal
  /// is an **ordinary outcome of concurrent agency**, not an error. A `null`
  /// [expected] means *the ref must not exist*.
  ///
  /// This is also the emission point of every event: the armed shim rides the
  /// `reference-transaction` hook, so a refusal here fires `.refused` and a
  /// success fires `.landed`, locally and on the receiving side of a push
  /// alike.
  bool updateRef(
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

  /// The commits reachable from [ref], newest first.
  List<RawCommit> log(String gitDir, {required String ref, int? limit});

  /// One commit's record.
  RawCommit showCommit(String gitDir, Commit commit);

  /// What changed between two commits — always derived, never stored.
  Diff diffTree(String gitDir, {required Commit from, required Commit to});

  /// Checks [ref] out at [path] as a worktree of this repository. The object
  /// store is shared, so the history is stored once however many worktrees
  /// stand at once; only the files are copied.
  void worktreeAdd(String gitDir, {required String path, required Commit at});

  /// Discards the worktree at [path] and deregisters it. Leaving it registered
  /// is the leak the API exists to prevent.
  void worktreeRemove(String gitDir, {required String path});

  /// The declared remotes.
  List<Remote> remotes(String gitDir);

  /// Declares a remote. Declaring is not electing: which copy is authoritative
  /// is said elsewhere, and this only records where bytes may travel.
  void addRemote(String gitDir, {required String name, required String url});

  /// Copies a repository from [source] into [gitDir]. Crosses the network.
  Future<void> clone(String source, String gitDir, {bool bare = true});

  /// Sends refs to [remote]. The receiving side runs its own hook and may
  /// refuse, which is federation using exactly the mechanism local action uses.
  Future<void> push(String gitDir, {required String remote, String? ref});

  /// Brings refs down from [remote]. Nothing is merged: what arrives is
  /// another participant's line, and joining lines is an act of its own.
  Future<void> fetch(String gitDir, {required String remote});
}
