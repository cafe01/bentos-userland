import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../place/place.dart';
import 'arming/arming.dart';
import 'dispatch.dart';
import 'event.dart';
import 'transaction.dart';
import '../git/git_ambient.dart';
import 'instance.dart';
import 'manifest.dart';
import 'materialization.dart';
import '../git/model/commit.dart';
import '../git/model/remote.dart';

/// One named thing of an application's ontology, and **the class**.
///
/// An entity is a **thing**, never a who: it is written to, read, versioned,
/// carried, and it never acts. Physically it is one Git repository, **bare** —
/// an instance is a ref and its state is a worktree, so a default checkout at
/// the root would lie about which of the two it is. The repository is the
/// class; its refs are its [instances], each a ref whose tree is the object's
/// state.
///
/// The RAM is the disk: the developer's object model survives intact while the
/// object becomes durable, addressable, versioned and federated. Nothing
/// executes it, so the entity has no methods — only actions done to it and the
/// events those acts publish.
///
/// # The class is the API
///
/// A `final class`, like `Place`, and for the same reason: the entity *is* a
/// Git repository and there will be no second implementation. What varies is
/// the substrate, and the substrate is what carries the abstraction — the `Git`
/// port, injected as a zone ambient, under this concrete surface.
///
/// # The handle law — anchor and referent
///
/// Taken whole from `Place`, because the two primitives are one idiom.
/// **A handle is cheap, resolves lazily, and creates nothing**: `Entity(name)`
/// is minted *at* an anchor and speaks *of* a referent — the nearest
/// installation found walking **up** the tree of places, nearest winning, as
/// `PATH`, `node_modules` and git's own config scopes all walk. Genesis is a
/// separate act: [create] installs at the anchor, `instance(id).create()`
/// births the ref.
///
/// Handles are **live**: every derived member re-reads, so a ref moved by
/// another process is seen on the next access.
///
/// # There is no public git directory
///
/// Exposing one hands back the exact footgun this API exists to close: a caller
/// holding it will run `git -C` itself, below the ontology, past the swap and
/// past the hook. The resolution is internal, always. The coreutil keeps a
/// named escape hatch (`entity path`) because a person may deliberately decide
/// to go below the ontology, and that decision should be visible when it is
/// taken — not available by accident to every consumer of a library.
final class Entity {
  /// A handle to the entity named [name], anchored at [from] (the working
  /// directory by default). Cheap, zero IO, creates nothing, and succeeds even
  /// where no installation exists — resolution happens lazily, on the first
  /// derived read.
  Entity(this.name, {String? from}) : _anchor = from;

  /// The DNS-notation name: wholly semantic, identifying and describing without
  /// binding. It is **not a location** — the same identity stands at many
  /// coordinates at once, and which copy is meant is what an anchor decides.
  final String name;

  /// The query point — internal state, surfaced by no member, exactly as
  /// `Place`'s anchor is. [create] consumes it; resolution walks up from it.
  final String? _anchor;

  /// The namespace the entity tenant is granted at a place. The one string that
  /// says where an installation's repository and tables live, and it is granted
  /// through the place's generic gate — the entity never constructs a path into
  /// another primitive's control plane.
  static const String plotNamespace = 'entity';

  /// The ref instances are born from, and where the manifest lives.
  static const String genesisRef = 'refs/heads/genesis';

  /// The name the entity was authored under, stated in genesis. A record, never
  /// a binding: the name is semantic and the same identity stands at many
  /// coordinates.
  static const String _entityTrailer = 'Bentos-Entity';

  /// What makes one authoring distinct from another of the same name.
  static const String _genesisTrailer = 'Bentos-Genesis';

  static final _entropy = math.Random.secure();

  static String _mintIdentity() => List.generate(
        4,
        (_) => _entropy.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
      ).join();

  /// Installs the entity here — authored, with no origin and nothing to fetch
  /// from. The one member that consumes the anchor; by liveness this same
  /// handle then resolves to what it just made.
  Entity create() {
    final place = Place(_anchor ?? Directory.current.path);
    final gitDir = p.join(place.plot(plotNamespace).path, name, repositoryDirName);
    ambientGit.init(gitDir);
    final genesisSha = _bearGenesis(gitDir, name);
    // The tenant asks; the landlord records. The gitlink is the place's own
    // tree entry and no tenant writes there.
    place.register(name, url: '', path: name, sha: genesisSha.sha);
    ArmingTables(gitDir, entity: name).ensureArmed();
    // An authored entity's genesis is empty, and the stage is stood up all the
    // same: what it buys is that the tree *exists and follows the ref* from the
    // first moment, so the author who writes a manifest and lands it has a tree
    // to bring forward rather than an absence with no verb pointed at it.
    stageClass();
    return this;
  }

  /// The ref instances are born from: the class's structure, empty until a
  /// manifest is written into it. A first swap against *no ref at all*, which is
  /// how a genesis refuses to happen twice.
  ///
  /// **Genesis carries an identity of its own**, and it must. `create` authors
  /// an entity with no origin, so two people who each author `bentos.llm` have
  /// made two things that share a name — two participants, never two views. A
  /// genesis with no identity would be byte-identical under content addressing,
  /// and the two lines would then federate as though they were one, silently.
  /// The token is what makes that impossible.
  static Commit _bearGenesis(String gitDir, String name) {
    final empty = Directory.systemTemp.createTempSync('entity-genesis-');
    try {
      final tree = ambientGit.writeTree(gitDir, workTree: empty.path);
      final sha = ambientGit.commitTree(
        gitDir,
        tree: tree,
        parents: const [],
        message: 'genesis\n\n$_entityTrailer: $name\n'
            '$_genesisTrailer: ${_mintIdentity()}\n',
      );
      ambientGit.updateRef(
        gitDir,
        ref: genesisRef,
        newCommit: Commit(sha),
        expected: null,
      );
      return Commit(sha);
    } finally {
      empty.deleteSync(recursive: true);
    }
  }

  /// Brings a copy of an entity that exists elsewhere into a place: the clone,
  /// its registration as the place's submodule, and the arming of whatever its
  /// manifest declares. **The common act** — a platform's ordinary day is
  /// bringing in what someone else made.
  ///
  /// One act with two halves, and the halves have different owners: the clone
  /// and the arming are the entity's, the registration and the pin are the
  /// place's, because the gitlink lives in the place's own tree and no tenant
  /// writes there. The composite is the entity's verb all the same.
  ///
  /// **It does not materialize.** A federated site that only reacts holds no
  /// worktree at all; bringing the tree down is the place's own recursive verb,
  /// performed when someone means to look.
  ///
  /// Asynchronous: it crosses the network.
  ///
  /// **`source` is a fetch address and never a name to resolve** — a local
  /// path, a host, a forge, exactly as Git accepts it, taken to
  /// [ambientGit.clone] verbatim. Nothing here turns a bare name into a
  /// lookup: the precedence below only ever *names what already arrived*.
  ///
  /// **Naming has a precedence, and the manifest sits in the middle of it.**
  /// `as` overrides; absent that, the freshly cloned entity's own
  /// [Manifest.name] answers, since a thing that says its own name deserves
  /// to be believed over a guess; only when neither speaks does the source
  /// URL's own basename stand in. Reading the manifest needs bytes already on
  /// disk, so a name that depends on it cannot share the clone's final
  /// address with a name that doesn't — hence the stage: cloned once to a
  /// disposable directory, read there, then cloned again — locally, cheaply —
  /// into the place at the name now decided. `--as` skips the stage
  /// entirely, since nothing about its name depends on the content.
  static Future<Entity> install(
    String source, {
    String? at,
    String? as,
    void Function(String complaint)? warn,
  }) async {
    final place = Place(at ?? Directory.current.path);
    final String name;
    final String gitDir;
    if (as != null) {
      name = as;
      gitDir = p.join(place.plot(plotNamespace).path, name, repositoryDirName);
      _refuseIfTaken(place, name, gitDir);
      await ambientGit.clone(source, gitDir);
      _ensureGenesis(gitDir);
    } else {
      final staging = Directory.systemTemp.createTempSync('entity-install-');
      final stagingGitDir = p.join(staging.path, repositoryDirName);
      try {
        await ambientGit.clone(source, stagingGitDir);
        _ensureGenesis(stagingGitDir);
        name = _declaredName(stagingGitDir) ?? _nameFromSource(source);
        gitDir = p.join(place.plot(plotNamespace).path, name, repositoryDirName);
        // Asked here, where the name is finally known and before one byte has
        // been written into the place: the staging clone is ours and disposable,
        // so a refusal from this line leaves the site exactly as it stood.
        _refuseIfTaken(place, name, gitDir);
        await ambientGit.clone(stagingGitDir, gitDir);
        _ensureGenesis(gitDir);
      } finally {
        if (staging.existsSync()) staging.deleteSync(recursive: true);
      }
    }
    place.register(
      name,
      url: source,
      path: name,
      sha: ambientGit.revParse(gitDir, genesisRef)?.sha ?? '',
    );
    ArmingTables(gitDir, entity: name).ensureArmed();
    // No *instance* is checked out: a site that only reacts holds no instance
    // worktree at all, and bringing one down is the place's own recursive verb.
    // The class is the other half — its tree is where the executables the
    // manifest names actually stand, and arming has just written lines that
    // point at them.
    final installed = Entity(name, from: place.root.path);
    // The class first, the table after: arming writes lines that point at
    // bodies, and a line armed before its body stands is a window in which an
    // act wakes something that is not there yet.
    installed.stageClass();
    installed._armDeclared(place, warn: warn);
    return installed;
  }

  /// Refuses to install over an installation that already stands here.
  ///
  /// **Two states, and neither is ours to overwrite.** A registered name is an
  /// installation someone made, with its own tables, its own remotes and
  /// possibly its own line of history — clobbering it is not what a second
  /// `install` means, and what it *does* mean (fetch, re-stage, re-arm) is a
  /// verb of its own that does not exist yet. A directory standing with no
  /// registration is stranger still: nothing here knows what it is, so it is
  /// named and left exactly where it is.
  ///
  /// The value of saying it here is the shape of the alternative. Without this,
  /// the answer was the substrate's own — an unhandled `git clone` failure, a
  /// stack trace and exit 255 — which names no cure and no owner, and which a
  /// script cannot branch on.
  static void _refuseIfTaken(Place place, String name, String gitDir) {
    if (place.lookup(name) != null) {
      throw EntityAlreadyInstalled(name, place.root.path);
    }
    final standing = Directory(p.dirname(gitDir));
    if (standing.existsSync() && standing.listSync().isNotEmpty) {
      throw EntityAlreadyInstalled(
        name,
        place.root.path,
        unregistered: standing.path,
      );
    }
  }

  /// Arms what the manifest declares: for every function that names both an
  /// executable and the landings it reacts to, one line pointing at `entity
  /// run`.
  ///
  /// **This is why the manifest has a function table at all.** A reaction
  /// declared in band travels with the entity, so a site that installs it reacts
  /// without anybody writing a line by hand — and the per-seat `arm` that each
  /// face used to perform in its own code becomes a *reading*, performed once,
  /// by the installer.
  ///
  /// Armed on `*`, and that is not a lost instance: at install time no instance
  /// exists, and the one the event lands on reaches the woken command through
  /// the environment the shim exports. A line that named an instance could only
  /// ever have been armed after the fact, which is the debt this closes.
  ///
  /// It arms **this manifest only**. Composition is transitive and a fused body
  /// would have to be walked to be armed, but `is:` has no emitter yet — a
  /// traversal written against nothing is a shape nobody demonstrated.
  ///
  /// A row that is not a legible event pattern is **complained about, never
  /// dropped in silence**: the entity is installed and everything legible is
  /// armed, because one misspelled reaction is not a reason to refuse a
  /// platform's ordinary act.
  void _armDeclared(Place place, {void Function(String complaint)? warn}) {
    final Manifest declared;
    try {
      declared = manifest;
    } on Object {
      // No manifest at all is the ordinary condition of a freshly authored
      // entity, and an entity that declares nothing declares no reactions.
      return;
    }
    final tables = ArmingTables(_gitDir, entity: name);
    for (final entry in declared.reactions.entries) {
      final function = entry.key;
      if (declared.functions[function] == null) {
        warn?.call(
          "$name: '$function' declares reactions and no executable — "
          'nothing was armed for it',
        );
        continue;
      }
      for (final text in entry.value) {
        final EventPattern pattern;
        try {
          pattern = EventPattern.parse(text.trim());
        } on FormatException catch (e) {
          warn?.call("$name: '$function' declares on: $text — ${e.message}");
          continue;
        }
        tables.add(
          instance: '*',
          pattern: pattern,
          // Resolved by the substrate's PATH when the line fires, which is the
          // same law a hand-armed bare name lives under. The vantage is written
          // out because a hook fires from a working directory nobody chose, and
          // a bare name would resolve up from wherever that happens to be.
          command: ['entity', '-C', place.root.path, 'run', name, function],
          provenance: Provenance.manifest,
        );
      }
    }
  }

  /// **A clone brings history, never a class born here** — a foreign
  /// repository owes no `genesis` branch, only the ordinary root its own
  /// history already has. Where no genesis ref exists yet, this names one:
  /// the commit `HEAD`'s first-parent line ends at, the one honest answer to
  /// *where did this line come from*. Idempotent — an existing genesis, own
  /// or already carried over by a prior clone in this same install, is left
  /// exactly as it stands.
  static void _ensureGenesis(String gitDir) {
    if (ambientGit.revParse(gitDir, genesisRef) != null) return;
    if (ambientGit.revParse(gitDir, 'HEAD') == null) return;
    final history = ambientGit.log(gitDir, ref: 'HEAD');
    if (history.isEmpty) return;
    ambientGit.updateRef(
      gitDir,
      ref: genesisRef,
      newCommit: Commit(history.last.sha),
      expected: null,
    );
  }

  /// The name a just-cloned entity declares of itself, or `null` when it
  /// declares nothing — a freshly authored entity's ordinary condition, and
  /// never a throw: tolerant of there being nothing there yet, exactly as a
  /// reader displaying a manifest must be.
  static String? _declaredName(String gitDir) {
    final at = ambientGit.revParse(gitDir, genesisRef);
    if (at == null) return null;
    try {
      final manifest = Manifest.parse(
        String.fromCharCodes(ambientGit.catFile(gitDir, '${at.sha}:${Manifest.path}')),
      );
      return manifest.name.isEmpty ? null : manifest.name;
    } on Object {
      return null;
    }
  }

  /// The name a source implies when none is given: the repository's own, minus
  /// the substrate's suffix.
  static String _nameFromSource(String source) {
    final base = p.basename(source.endsWith('/')
        ? source.substring(0, source.length - 1)
        : source);
    if (base != repositoryDirName) {
      return base.endsWith('.git') ? base.substring(0, base.length - 4) : base;
    }
    // `<plot>/<name>/repo.git` — the layout's own shape, so the name is the
    // directory the repository stands in.
    return p.basename(p.dirname(source));
  }

  /// What the thing says it is, read from the genesis tree. The entity system's
  /// only contract, carried in band.
  Manifest get manifest {
    final gitDir = _gitDir;
    final at = ambientGit.revParse(gitDir, genesisRef);
    if (at == null) throw StateError('no genesis: $name');
    return Manifest.parse(
      String.fromCharCodes(
        ambientGit.catFile(gitDir, '${at.sha}:${Manifest.path}'),
      ),
    );
  }

  /// The genesis commit — the class's uninitialized structure.
  Commit get genesis {
    final at = ambientGit.revParse(_gitDir, genesisRef);
    if (at == null) throw StateError('no genesis: $name');
    return at;
  }

  /// The objects of this class. **Genesis is not among them**: it is the
  /// structure instances are born from, not one of them.
  List<Instance> get instances {
    const genesisName = 'genesis';
    return [
      for (final ref in ambientGit.branches(_gitDir))
        if (ref != genesisName) Instance(this, ref),
    ];
  }

  /// A handle to one instance. Creates nothing; the instance need not exist.
  Instance instance(String id) => Instance(this, id);

  /// Puts **the class** into the materialized condition: the entity's own tree
  /// at [at], standing at [path] — the tenant's half of bringing a constellation
  /// down, which the place's recursive verb composes with its own enumeration.
  ///
  /// What commit [at] is, is the caller's word and never this primitive's: a
  /// place materializes what it declares, and an entity has no opinion about
  /// which of its commits someone else holds it at. Hence no ref on the way
  /// out — the tree follows nothing, and re-materializing is the declarer
  /// asking again.
  ///
  /// **Present means update, never re-clone.** A worktree already standing here
  /// is moved to [at]; the repository is untouched either way, because throwing
  /// away a tree someone may be looking at is not what *bring this up to date*
  /// means. A directory that stands here and is no worktree of ours is not ours
  /// to delete, and the substrate's refusal travels.
  Materialization materialize(Commit at, {required String path}) {
    final gitDir = _gitDir;
    // Ours and not merely *somebody's*: the question is whether this repository
    // holds a tree here, and a directory that answers with another repository —
    // or with none — is not this verb's to discard.
    if (ambientGit.worktreeRepository(path) == gitDir) {
      ambientGit.worktreeRemove(gitDir, path: path);
    }
    ambientGit.worktreeAdd(gitDir, path: path, at: at);
    return Materialization(
      directory: Directory(path),
      gitDir: gitDir,
      ref: null,
    );
  }

  /// The directory the class's own tree stands in, beside the repository — the
  /// **stage**, and the one place a caller looks for the executables the
  /// manifest names.
  static const String classDirName = 'genesis';

  /// Puts **the class** on disk at the genesis this installation holds: the
  /// half of installing that makes running possible at all, since an executable
  /// needs a file and a bare repository has no files.
  ///
  /// **This is not the law it looks like it contradicts.** *Install does not
  /// materialize* is about **instances** — a federated site that only reacts
  /// holds no instance worktree, and still holds none after this. The class is
  /// the opposite case: a site that only reacts is precisely the one whose
  /// armed lines point at a body, so it needs the class's tree *more* than a
  /// site that looks. Instance stays the looker's; class comes with the
  /// installation.
  ///
  /// Idempotent by [materialize]'s own law — present means update, and a
  /// directory that is not ours is refused rather than discarded.
  ///
  /// An entity with no genesis stages nothing: there is no tree to stand up,
  /// and the ordinary condition of a repository cloned from a line that never
  /// had one is not a fault to throw on.
  Materialization stageClass() {
    final at = ambientGit.revParse(_gitDir, genesisRef);
    return at == null ? stagedClass : materialize(at, path: _stagePath);
  }

  /// The class's tree as it presently stands — **asked of the disk**, like every
  /// materialization, so that *is this installation runnable* is a question
  /// about the machine rather than about what some process remembered.
  ///
  /// **It follows [genesisRef], and that is the whole difference from a place's
  /// pin.** The manifest is read at the ref; the executables must therefore come
  /// from the same commit, or contract and bytes disagree with nothing to say
  /// so. Following a ref is also what gives staleness a cure that already
  /// exists — a tree that follows nothing can only be re-declared.
  Materialization get stagedClass => Materialization(
        directory: Directory(_stagePath),
        gitDir: _gitDir,
        ref: genesisRef,
      );

  String get _stagePath => p.join(p.dirname(_gitDir), classDirName);

  /// Arms a listener at this installation: when an act matching one of [events]
  /// occurs, [command] is run with the occurrence appended.
  ///
  /// **A command line, never a closure** — the listener is resurrected by a
  /// shell shim in another process, so a Dart function could never be it. What
  /// this writes is a line in the installation's table, and the phase in the
  /// pattern decides which table: `.attempted` listeners run inside the
  /// transaction and may refuse, `.landed` listeners are woken detached.
  ///
  /// [instance] selects which object is watched; `*`, the default, watches
  /// every one. Arming is **per installation**, never entity content and never
  /// tracked, which is what lets one site run a workload while another only
  /// watches with one line of difference.
  Registration on(
    Set<EventPattern> events, {
    required List<String> command,
    String instance = '*',
  }) =>
      _arm(events, command: command, instance: instance, once: false);

  /// Arms [command] the same way, with its own removal attached: the line is
  /// gone the moment it fires.
  ///
  /// **The only lifecycle the floor offers a subscriber.** Everything else
  /// about a listener's life belongs to the actor — a standing process is an
  /// actor with a body of its own, and nothing here holds a notion of a live
  /// one. What this serves is the caller that wants exactly the next
  /// occurrence: a face that types a turn and falls into a monitor until the
  /// reaction it waited for arrives.
  ///
  /// One line per pattern, so arming on two events and having one fire leaves
  /// the other armed. Whoever wants both spent together is describing an actor,
  /// not a registration.
  Registration once(
    Set<EventPattern> events, {
    required List<String> command,
    String instance = '*',
  }) =>
      _arm(events, command: command, instance: instance, once: true);

  Registration _arm(
    Set<EventPattern> events, {
    required List<String> command,
    required String instance,
    required bool once,
  }) {
    if (events.isEmpty) {
      throw ArgumentError.value(events, 'events', 'arm on at least one');
    }
    final tables = ArmingTables(_gitDir)..ensureArmed();
    Registration? first;
    for (final pattern in events) {
      final armed = tables.add(
        instance: instance,
        pattern: pattern,
        command: command,
        once: once,
      );
      first ??= armed;
    }
    return first!;
  }

  /// Publishes a ref transaction into the primitive: journals every triple in
  /// [updates], matches each against this installation's tables for [phase], and
  /// dispatches.
  ///
  /// **The trampoline's only callee**, and the whole content of *the hook
  /// publishes*. What the shim keeps is the contract with Git and its own
  /// self-location; matching, lifetimes, provenance, detaching, journaling and
  /// the woken body's context are all [Dispatch]'s, once.
  ///
  /// The return value is the exit code Git decides the transaction by: non-zero
  /// at [EventPhase.attempted] aborts it whole. At the other two phases the work
  /// is detached before this returns, so it is always `0`.
  Future<int> emit(EventPhase phase, Iterable<TransactionRefUpdate> updates) {
    final (place: place, gitDir: gitDir) = _installation;
    return Dispatch(entity: this, gitDir: gitDir, place: place)
        .emit(phase, updates);
  }

  /// Disarms the registration [id]. Idempotent.
  void off(String id) => ArmingTables(_gitDir).remove(id);

  /// What is armed here.
  List<Registration> get listeners => ArmingTables(_gitDir).all;

  /// Where bytes may travel. Not who is authoritative — that is declared, never
  /// computed, and `origin` is a default rather than a truth.
  List<Remote> get remotes => ambientGit.remotes(_gitDir);

  /// Gives an entity created here an origin and pushes to it. The push moves
  /// bytes; that the remote is now authoritative is a declaration, and never a
  /// consequence of the mechanism.
  Future<void> publish(String remote) async {
    final gitDir = _gitDir;
    // [remote] is where bytes may travel — a URL. It is declared as `origin`
    // because that is the default a reader expects, and declaring is not
    // electing: which copy is authoritative is said elsewhere.
    const named = 'origin';
    final declared = ambientGit.remotes(gitDir).any((r) => r.name == named);
    if (!declared) ambientGit.addRemote(gitDir, name: named, url: remote);
    await ambientGit.push(gitDir, remote: named);
  }

  /// The directory name the bare repository stands under, inside the plot. The
  /// worktree half of an installation stands in the place's tree; this half is
  /// infrastructure and never travels, which is what keeps a pin honest —
  /// nothing inside a control plane can be tracked by the tree above it.
  static const String repositoryDirName = 'repo.git';

  /// The resolved installation's repository: the walk **up** the tree of places
  /// to the first one that answers to [name]. Nearest wins, so an installation
  /// lower down shadows one above — `PATH`, `node_modules`, git's own config
  /// scopes, and this.
  ///
  /// Deliberately private, and the reason [gitDirOf] exists at all: the whole
  /// point of the API is that no caller holds this.
  String get _gitDir => _installation.gitDir;

  /// The resolved installation, **both halves**: the place that answered and the
  /// repository inside its plot.
  ///
  /// The walk is `_gitDir`'s, and it is written here because a body dispatch
  /// wakes is told where it stands (`BENTOS_PLACE`) — the place that answered
  /// for *this* installation, which only the walk knows and which a caller
  /// re-deriving from the repository's path would be decoding a plot's layout to
  /// guess.
  ({String place, String gitDir}) get _installation {
    final anchor = _anchor ?? Directory.current.path;
    for (Place? place = Place(anchor); place != null; place = place.parent) {
      if (place.lookup(name) == null) continue;
      return (
        place: place.root.path,
        gitDir: p.join(place.plot(plotNamespace).path, name, repositoryDirName),
      );
    }
    throw EntityNotInstalled(name, anchor);
  }

  @override
  String toString() => name;
}

/// No installation answering to a name was found on the walk up from an anchor.
///
/// A resolution failure and not a missing file: the same name may be installed
/// one place higher, at another site, or nowhere at all, and the anchor is half
/// the question. Both halves are reported, because "entity not found" without
/// the vantage it was not found from is unactionable.
final class EntityNotInstalled implements Exception {
  const EntityNotInstalled(this.name, this.anchor);

  final String name;
  final String anchor;

  @override
  String toString() => 'entity not installed: $name (searched up from $anchor)';
}

/// An installation of this name already stands at this place.
///
/// **A refusal and not a fault**: nothing was cloned, nothing was registered,
/// nothing was armed, and the answer a script must be able to branch on is *I
/// did not touch what is there*. The same reading `WorktreeNotOurs` gets, for
/// the same reason.
final class EntityAlreadyInstalled implements Exception {
  const EntityAlreadyInstalled(this.name, this.place, {this.unregistered});

  final String name;
  final String place;

  /// The directory standing in the way when **no registration** explains it —
  /// the stranger case, reported by path because only whoever put it there
  /// knows what it is.
  final String? unregistered;

  @override
  String toString() => unregistered == null
      ? '$name is already installed at $place'
      : '$name cannot be installed at $place: '
          'a directory stands at $unregistered that this place never registered';
}

/// The internal escape hatch — **not exported** from `lib/entity.dart`.
///
/// The coreutil's `entity path` verb and the arming machinery live in this
/// package and genuinely need the repository, while no consumer outside it may
/// have one. Dart has no package-private, so the seam is drawn here explicitly:
/// one named function, one line of the barrel file hiding it, and a reader who
/// can see the whole boundary at once.
String gitDirOf(Entity entity) => entity._gitDir;
