import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../place/place.dart';
import 'arming/arming.dart';
import 'event.dart';
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
    ArmingTables(gitDir).ensureArmed();
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
  static Future<Entity> install(String source, {String? at, String? as}) async {
    final place = Place(at ?? Directory.current.path);
    final name = as ?? _nameFromSource(source);
    final gitDir = p.join(place.plot(plotNamespace).path, name, repositoryDirName);
    await ambientGit.clone(source, gitDir);
    place.register(
      name,
      url: source,
      path: name,
      sha: ambientGit.revParse(gitDir, genesisRef)?.sha ?? '',
    );
    ArmingTables(gitDir).ensureArmed();
    // Nothing is checked out: a site that only reacts holds no worktree at all,
    // and bringing the tree down is the place's own recursive verb.
    return Entity(name, from: place.root.path);
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
    if (ambientGit.worktreeRepository(path) != null) {
      ambientGit.worktreeRemove(gitDir, path: path);
    }
    ambientGit.worktreeAdd(gitDir, path: path, at: at);
    return Materialization(
      directory: Directory(path),
      gitDir: gitDir,
      ref: null,
    );
  }

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
  String get _gitDir {
    final anchor = _anchor ?? Directory.current.path;
    for (Place? place = Place(anchor); place != null; place = place.parent) {
      if (place.lookup(name) == null) continue;
      return p.join(place.plot(plotNamespace).path, name, repositoryDirName);
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

/// The internal escape hatch — **not exported** from `lib/entity.dart`.
///
/// The coreutil's `entity path` verb and the arming machinery live in this
/// package and genuinely need the repository, while no consumer outside it may
/// have one. Dart has no package-private, so the seam is drawn here explicitly:
/// one named function, one line of the barrel file hiding it, and a reader who
/// can see the whole boundary at once.
String gitDirOf(Entity entity) => entity._gitDir;
