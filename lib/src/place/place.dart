import 'dart:io';

import 'package:path/path.dart' as p;

import 'home_ambient.dart';
import 'model/place_meta.dart';

/// A place — a marked region of the filesystem, the spatial primitive of the
/// OS. A true peer of [File] and [Directory]: the class is the API.
///
/// # What a place is
///
/// A directory is a place iff it carries the `.place/` marker. Places nest:
/// the filesystem is a habitat of places within places, and unmarked
/// directories between them are spatial voids — inside a place, but not
/// places themselves. Resolution never returns "nowhere": the machine root
/// and the logged-in home materialize as *implicit* places even unmarked, so
/// every path on the machine is enclosed by some place.
///
/// # The identity law — anchor and referent (the Git idiom)
///
/// `Place(path)` is a handle obtained *at* `path` but *to* the place
/// enclosing it — as a hypothetical `Git(interiorPath)` is a handle to the
/// one repo from anywhere inside it. The constructor argument is only the
/// **anchor** (the query point — internal, surfaced by no member); every
/// derived member speaks of the **referent**, the resolved root.
/// `Place('/repo')` and `Place('/repo/nested/deep')` are distinct handles to
/// the same place: same [root], same [name], same [ancestors] — and, the
/// load-bearing consequence, the same [plot] for any consumer. A consumer's
/// state at a place must be one slice no matter which interior path the
/// handle was minted at; anchor-identity would split it per working
/// directory, which is exactly the bug class this law kills.
///
/// Three corollaries:
///
/// - **There is no `path` member.** It would read "where this place is"
///   while answering with the anchor. The canonical location is [root].
/// - **`==` is not overridden** (neither does `dart:io`): equality by
///   referent would demand IO inside `==`. Test sameness through the
///   referent: `a.root.path == b.root.path`.
/// - **There is no `exists`.** Under never-nowhere, resolution cannot fail;
///   the information lives honestly in [isImplicit].
///
/// # Handles are live
///
/// Like `File.existsSync()` stats the disk on every call, every derived
/// member re-derives on access. A handle is a lens on the filesystem, never
/// a snapshot: [create] here — or an external `rm -rf .place/` — is observed
/// by every existing handle on its next read.
///
/// # The spatial law and its consumers
///
/// Place is a primitive of **spatial computation**: marking, resolution, the
/// ancestor chain, and land grants. It privileges no consumer — `mem`, `tx`,
/// `manifest`, and any third party are tenants surfing the spatial topology
/// through one generic gate, [plot]. The primitive never learns what a
/// tenant stores; no consumer ever constructs a `.place/…` path or walks
/// directories itself. That seam is what keeps the marker, the internal
/// layout, and the future substrate swappable.
///
/// The surface walks **up only** ([parent], [ancestors]) — cheap,
/// deterministic path law. Descent ("which places nest inside me") is a
/// filesystem scan, a different cost class entirely, and lives in a survey
/// layer over the primitive, never on the handle. The asymmetry is
/// deliberate.
///
/// # The superrepo half — designed, not built
///
/// A place is also a Git superrepo, and the half that says so knows that
/// entities exist, their names, their origins and the commits it holds them
/// at — and nothing of what is inside them. It is **structural on both
/// counts**. Every member of it throws [UnimplementedError] today: the contract
/// is stated, the bodies are construction's, and the spatial half above is
/// untouched and in use.
///
/// # Hermeticity
///
/// Built on raw `dart:io`; testability rides [IOOverrides], exactly as
/// `File`/`Directory` themselves. The one ambient fact `IOOverrides` does
/// not cover — the logged-in home, needed to materialize the implicit home
/// place — is read as a zone-scoped ambient with a `Platform.environment`
/// fallback. No constructor carries a filesystem or a home.
///
/// The surface is deliberately **sync-only**, a declared divergence from
/// async-first `dart:io`: place facts are a handful of tiny stats and one
/// small yaml; async ceremony would cost call sites more than the IO costs
/// the process.
final class Place {
  /// Creates a handle anchored at [anchorPath] — cheap, zero IO, creates
  /// nothing, succeeds even if the path does not exist. Resolution happens
  /// lazily, on the first derived read.
  Place(String anchorPath) : _anchor = anchorPath;

  /// The query point — internal state, surfaced by no member. [create] and
  /// resolution consume it; a caller that needs it kept the string it
  /// constructed with.
  final String _anchor;

  /// The marker directory name. A directory is a place iff it contains this.
  static const _markerName = '.place';

  /// The place enclosing the working directory —
  /// `Place(Directory.current.path)`.
  static Place get current => Place(Directory.current.path);

  /// The referent: the nearest enclosing `.place/`-marked directory, walking
  /// up from the anchor. Never nowhere — an unmarked walk terminates at the
  /// implicit home (when the anchor sits under it) or the machine root.
  Directory get root => Directory(_resolve().root);

  /// True when the referent materialized without a marker (the machine root
  /// or the logged-in home as implicit places).
  bool get isImplicit => _resolve().implicit;

  /// The nearest enclosing place above the referent; null only at the
  /// machine root.
  Place? get parent {
    final chain = ancestors;
    return chain.isEmpty ? null : chain.first;
  }

  /// The ordered ancestor chain, nearest parent → the machine root. Contains
  /// only places — unmarked intermediate directories are not in it — and
  /// excludes this place. Includes the implicit home when the place sits
  /// under home. Empty for the place at the machine root.
  List<Place> get ancestors {
    final chain = <Place>[];
    var path = root.path;
    while (true) {
      final parentDir = p.dirname(path);
      if (parentDir == path) break;
      path = parentDir;
      final atRoot = p.dirname(path) == path;
      if (_isMarked(path) || _isHome(path) || atRoot) chain.add(Place(path));
    }
    return chain;
  }

  /// The place's name: the metadata's, else the referent's directory name
  /// (else the path, for the machine root). Lazy from `.place/place.yaml`;
  /// malformed metadata degrades to defaults with a surfaced warning, never
  /// a crash.
  String get name {
    final declared = _meta.name;
    if (declared != null) return declared;
    final base = p.basename(root.path);
    return base.isEmpty ? root.path : base;
  }

  /// Free-form description from the metadata, if declared.
  String? get description => _meta.description;

  /// The declaring owner from the metadata, if declared.
  String? get owner => _meta.owner;

  /// Surfaced when `place.yaml` is present but unparseable; null otherwise —
  /// the warning [name] and friends swallow while degrading to defaults.
  String? get metaWarning => _meta.warning;

  /// The land grant — the one generic gate through which every consumer
  /// derives its private storage at this place.
  ///
  /// Returns the handle to [namespace]'s slice under the place's control
  /// plane. Pure path law on the referent: creates nothing (the tenant
  /// materializes on first write), reads nothing (the primitive is blind to
  /// what a slice contains). Two handles anchored anywhere inside one place
  /// return the same plot — the identity law's load-bearing consequence.
  ///
  /// **The return type is a boundary decision: an opaque [Directory], not a
  /// [Place].** Returning a place would re-privilege spatiality over the
  /// tenant's own shape — a plot with plots of its own, recursion instead of
  /// opacity. Below the returned directory the tenant is the absolute owner
  /// of the layout: `mem` lays out `<entity>/…`, `tx` lays out
  /// `<entity>/<scope>/…`, and the primitive never knows.
  ///
  /// [namespace] identifies the tenant and must be a single path segment —
  /// no separators, not `.` or `..`. The one law the primitive enforces at
  /// this gate; anything else would make the grant an escape hatch. Throws
  /// [ArgumentError] otherwise.
  ///
  /// Naming: `plot` is the spatial metaphor made literal — the ground the
  /// place grants a tenant. (`storage` was the considered alternative,
  /// rejected as administrative vocabulary that betrays the spatial frame.)
  Directory plot(String namespace) {
    if (namespace.isEmpty ||
        namespace == '.' ||
        namespace == '..' ||
        namespace.contains('/') ||
        namespace.contains(r'\')) {
      throw ArgumentError.value(
        namespace,
        'namespace',
        'must be a single path segment',
      );
    }
    return Directory(p.join(root.path, _markerName, namespace));
  }

  /// The namespaces holding a plot at this place — structural enumeration,
  /// consumer-blind: the primitive lists which tenants have ground here and
  /// interprets nothing below. Empty for a place with no grants, never an
  /// error.
  List<String> get plots {
    final marker = Directory(p.join(root.path, _markerName));
    try {
      return marker
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .toList()
        ..sort();
    } on FileSystemException {
      return const [];
    }
  }

  /// Marks the **anchor** — not the referent — as a place root: creates
  /// `.place/` and writes `place.yaml` from the given fields, [name]
  /// defaulting to the directory name. The one member that consumes the
  /// anchor: `Place('/repo/new').create()` promotes `/repo/new` itself, and
  /// by the liveness law this same handle's [root] then resolves there. A
  /// pre-existing marker is reported, never clobbered.
  Place create({String? name, String? description, String? owner}) {
    final anchor = _absoluteAnchor;
    final marker = Directory(p.join(anchor, _markerName));
    if (marker.existsSync()) return this;
    marker.createSync(recursive: true);
    final base = p.basename(anchor);
    final buf = StringBuffer()
      ..writeln('name: ${name ?? (base.isEmpty ? anchor : base)}');
    if (description != null) buf.writeln('description: $description');
    if (owner != null) buf.writeln('owner: $owner');
    File(p.join(marker.path, 'place.yaml')).writeAsStringSync(buf.toString());
    return this;
  }

  // ───────────────────────────────────────────────────────────────────────
  // The Git half — DESIGNED AND NOT BUILT.
  //
  // Every member below throws [UnimplementedError] by design, not by neglect:
  // the contract is the design chair's deliverable and the bodies are
  // construction's. The spatial half above is built and in use; nothing here
  // touches it.
  // ───────────────────────────────────────────────────────────────────────

  /// The entities installed here, as the current [timeline] declares them.
  ///
  /// **Enumeration, not interrogation.** A place knows that entities exist —
  /// their names, their origins, and the commits it holds them at — and knows
  /// nothing of what is inside them. That containment is a fact of the
  /// platform's ontology up to the altitude at which a person sees a desk with
  /// things on it, which is why the spatial primitive carries it while staying
  /// blind to content.
  ///
  /// The record is deliberately a record: **`Place` imports no type from the
  /// entity package**, so the dependency stays one-way (entity → place) and the
  /// gate speaks only names, URLs, paths and shas. What any of these *is* — its
  /// type, its actions, its instances — is read by the entity itself, through
  /// its own name resolution, which walks this same tree of places.
  List<({String name, String url, String path, String sha})> get installed =>
      throw UnimplementedError('Place.installed');

  /// The installation answering to [name] here, or null. The single step of the
  /// entity's upward walk; the walk itself belongs to the entity, because
  /// nearest-wins resolution is its law and not the place's.
  ({String name, String url, String path, String sha})? lookup(String name) =>
      throw UnimplementedError('Place.lookup');

  /// Records an entity as installed here: the gitlink in the place's tree and
  /// the address beside it.
  ///
  /// > **The tenant asks; the landlord records.**
  ///
  /// Installing is one act with two halves — the clone and the arming are the
  /// entity's, the registration and the pin are the place's, because the
  /// gitlink lives in the place's own tree and no tenant writes there. This is
  /// the half the landlord performs, and the reason there is no `place install`
  /// verb at any surface.
  ({String name, String url, String path, String sha}) register(
    String name, {
    required String url,
    required String path,
    required String sha,
  }) =>
      throw UnimplementedError('Place.register');

  /// Moves an installation's pin to [sha].
  ///
  /// The mechanism only. **When a place advances a pin is a policy, and it is
  /// the one thing this surface deliberately does not decide** — whose rule
  /// calls this is not yet ours to state.
  void pin(String name, String sha) => throw UnimplementedError('Place.pin');

  /// Forgets an installation. Structural: the plot's contents are not this
  /// primitive's to delete, because what a tenant keeps under its grant is the
  /// tenant's alone.
  void unregister(String name) => throw UnimplementedError('Place.unregister');

  /// The timelines this place holds. A place's branch means **time** and always
  /// will — a configuration of the constellation — which is what distinguishes
  /// it from an entity's branch, whose meaning is the application's word.
  /// Timelines are cheap, and several stand at once.
  List<String> get timelines => throw UnimplementedError('Place.timelines');

  /// The timeline in view — the configuration [installed] reports.
  String get timeline => throw UnimplementedError('Place.timeline');

  /// Brings the constellation down: the entities of this place at their pins
  /// and, when [recursive], the tree of places beneath it too. This is what
  /// makes cloning a place take the whole macrocosm.
  ///
  /// Installing an entity does **not** do this — a site that only reacts never
  /// needs a worktree — and materializing is therefore a deliberate act,
  /// performed when someone means to look.
  ///
  /// The one asynchronous member of the whole surface, and the one place the
  /// sync/async law's second clause reaches `Place`: it fetches.
  Future<void> materialize({bool recursive = false}) =>
      throw UnimplementedError('Place.materialize');

  /// Metadata re-read on every access — a live handle never snapshots. The
  /// primitive owns where metadata lives; [PlaceMeta] only parses.
  PlaceMeta get _meta =>
      PlaceMeta.load(File(p.join(root.path, _markerName, 'place.yaml')));

  /// The anchor, absolute and normalized against the working directory.
  String get _absoluteAnchor {
    final a = p.normalize(_anchor);
    return p.isAbsolute(a) ? a : p.normalize(p.join(Directory.current.path, a));
  }

  /// The resolution walk: anchor → referent. Never nowhere.
  ({String root, bool implicit}) _resolve() {
    var path = _absoluteAnchor;
    while (true) {
      if (_isMarked(path)) return (root: path, implicit: false);
      final parentDir = p.dirname(path);
      if (_isHome(path) || parentDir == path) {
        return (root: path, implicit: true);
      }
      path = parentDir;
    }
  }

  /// True iff [path] itself carries the marker — a single stat, no upward
  /// walk. The whole-machine scan probes every directory this way, so it must
  /// stay O(1): resolving through a handle ([isImplicit]/[root]) would walk to
  /// the nearest enclosing place on every unmarked void, turning the scan
  /// O(depth). Keeps the `.place/` literal Place's secret; the caller never
  /// constructs it.
  static bool isMarkedAt(String path) => _isMarked(path);

  /// The marker probe. A whole-machine scan meets directories it cannot
  /// read — an unreadable probe is "not a place", never fatal.
  static bool _isMarked(String path) {
    try {
      return Directory(p.join(path, _markerName)).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  static bool _isHome(String path) => p.equals(path, ambientHome);
}
