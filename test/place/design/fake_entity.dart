// The entity, faked — the one collaborator this suite mocks.
//
// The place enters the entity through one gate (`CopyGate`, a zone-scoped
// ambient) and then holds `Copy` objects. This file fakes both: an in-memory
// `FakeGate` that answers `stand`, `author`, `at`, `manifestAt`, and a
// `FakeCopy` that records every call the place makes and answers from state
// the test seeded. Nothing here touches Git.
//
// Every type the fake implements is the entity's *compiled* contract
// (`lib/src/entity/contract/`), which is authoritative over any prose. The
// entity's value types are constructed only in this file, so that when the
// contract moves the drift is fixed here and nowhere else in the suite.
import 'dart:async';
import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart';
import 'package:bentos_userland/src/place/contract/copy_gate.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:file/file.dart' as f;
import 'package:path/path.dart' as p;

const Actor tester = Actor(name: 'Tester', address: 'tester@test.local');
const Actor other = Actor(name: 'Other', address: 'other@test.local');

/// Runs [body] hermetically with [gate] installed as the copy gate ambient.
Future<T> runPlace<T>(FakeGate gate, Future<T> Function(f.FileSystem fs) body) =>
    runInMemoryFs((fs) => runZoned(() => body(fs), zoneValues: {copyGateKey: gate}));

/// A point on an instance's line: an ordinal in the fake, opaque to the place.
Point pt(int n) => Point('p$n');
int ordinal(Point point) => int.parse((point as String).substring(1));

/// An instance a far address holds, as seeded into a `FakeRemote`.
final class Seed {
  const Seed(this.id, {this.title, this.born});
  final String id;
  final String? title;
  final DateTime? born;
}

/// What the copy knows of one instance's existence.
final class Known {
  Known(this.id, {this.title, this.contentHere = true, this.born, this.forkOf, this.forkAt});
  final String id;
  String? title;
  bool contentHere;
  DateTime? born;
  String? forkOf;
  Point? forkAt;
}

Manifest manifestOf(String name, {String kind = 'thing', bool ownDivergence = false}) => Manifest(
      name: name,
      kind: kind,
      instanceName: const InstanceNaming(fallback: 'untitled'),
      rhythm: const Rhythm(roles: {Role.publishTo, Role.follow}, cadence: ByHand()),
      reconciliation: ownDivergence ? ReconciliationRule(actor: Actor(name: 'merge', address: 'merge@$name'), run: 'merge') : null,
    );

/// A private area, on disk (the in-memory disk), landed by compare-and-swap.
final class FakeAct implements Act {
  FakeAct(this.copy, this.id, this.by, this.from, this.directory);
  final FakeCopy copy;
  final String id;
  final Actor by;
  @override
  final Point from;
  @override
  final Directory directory;

  @override
  Future<Outcome> land({String? say, String? title}) async {
    if (copy.gateWords != null) return Gated(rule: 'gate', words: copy.gateWords!);
    if (copy.diverge) return DivergedFrom(here: from, there: pt(ordinal(from) + 1));
    final now = copy.instance(id).here ?? pt(0);
    if (copy.moveUnderNext > 0) {
      copy.moveUnderNext--;
      return Moved(from: from, now: pt(ordinal(now) + 1));
    }
    if (now != from) return Moved(from: from, now: now);
    final files = <String, String>{};
    if (directory.existsSync()) {
      for (final e in directory.listSync(recursive: true, followLinks: false)) {
        if (e is File) files[p.relative(e.path, from: directory.path)] = e.readAsStringSync();
      }
    }
    copy.files[id] = files;
    final point = pt(copy.tip[id] = (copy.tip[id] ?? 0) + 1);
    final action = Action(point: point, actor: by, when: copy.clock(), say: say, title: title, arrivedFrom: null);
    copy.history.putIfAbsent(id, () => []).add(action);
    if (title != null) copy.known[id]!.title = title;
    copy.refresh(id);
    return Landed(action);
  }

  @override
  void abandon() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class FakeStateView implements StateView {
  FakeStateView(this.files);
  final Map<String, String> files;
  @override
  List<String> list(String path) {
    final prefix = path == '.' || path.isEmpty ? '' : '${p.normalize(path)}/';
    return files.keys.where((k) => k.startsWith(prefix)).map((k) => k.substring(prefix.length).split('/').first).toSet().toList();
  }

  @override
  Future<List<int>> read(String path) async => (files[p.normalize(path)] ?? '').codeUnits;
}

/// A handle onto one instance of a [FakeCopy]. Every member answers from the
/// copy's seeded state and records what the place asked.
final class FakeInstance implements Instance {
  FakeInstance(this.copy, this.id);
  final FakeCopy copy;
  @override
  final String id;

  Known get _known => copy.known[id] ?? (throw StateError('unborn instance $id'));

  @override
  String get title => copy.known[id]?.title ?? copy.manifest.instanceName.fallback;
  @override
  Birth get birth {
    final k = _known;
    final when = k.born ?? DateTime(2026);
    return k.forkOf == null
        ? FromGenesis(when: when, by: tester)
        : ForkedFrom(when: when, by: tester, instance: k.forkOf!, at: k.forkAt ?? pt(0));
  }

  @override
  Point? get here => copy.tip.containsKey(id) ? pt(copy.tip[id]!) : null;
  @override
  Map<String, Point> get atSources => {for (final s in copy.sources) s.name: here ?? pt(0)};

  @override
  Future<Instance> born({required Actor by, Point? from, String? title}) async {
    final parent = from == null ? null : copy.tip.entries.where((e) => pt(e.value) == from).map((e) => e.key).firstOrNull;
    copy.bornCalls.add((id, by, parent));
    copy.known[id] = Known(id, title: title, born: copy.clock(), forkOf: parent, forkAt: from);
    copy.files[id] = Map.of(parent == null ? {} : (from == null ? {} : copy.filesAt(parent, from)));
    copy.tip[id] = 0;
    return this;
  }

  @override
  List<Action> history({Point? since}) {
    final h = copy.history[id] ?? const [];
    return since == null ? List.of(h) : h.where((a) => ordinal(a.point) > ordinal(since)).toList();
  }

  @override
  Future<StateView> read({required Point at}) async {
    if (!_known.contentHere && copy.unfetchable.contains(id)) {
      throw ContentUnavailable(id, tried: copy.sources.map((s) => s.address).toList());
    }
    return FakeStateView(copy.filesAt(id, at));
  }

  @override
  Point? pointAsOf(Instant when) {
    final n = (copy.history[id] ?? const []).where((a) => !a.when.isAfter(when)).length;
    return n == 0 ? null : pt(n);
  }

  @override
  Future<Act> beginAct({required Actor by}) async {
    final dir = Directory(p.join(copy.plot.path, 'acts', '$id-${copy.actCounter++}'))..createSync(recursive: true);
    for (final e in (copy.files[id] ?? const {}).entries) {
      File(p.join(dir.path, e.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
    return FakeAct(copy, id, by, here ?? pt(0), dir);
  }

  @override
  Future<Outcome> act(FutureOr<void> Function(Act) body, {required Actor by, String? say, String? title}) async {
    copy.actCalls.add((id, by, say));
    final a = await beginAct(by: by);
    await body(a);
    final outcome = await a.land(say: say, title: title);
    a.abandon();
    return outcome;
  }

  @override
  Standing standingAgainst(String source, {Point? from}) {
    copy.standingCalls.add((id, source, from));
    if (from != null) {
      final n = copy.pastPoint[source]?[id]?[from];
      if (n == null) return const Standing.unknown();
      return Standing.known(relation: n == 0 ? Relation.current : Relation.behind, behind: n, ahead: 0, contacted: copy.contacted[source] ?? copy.clock());
    }
    return copy.standings[source]?[id] ?? const Standing.unknown();
  }

  @override
  Map<String, Standing> get standing => {for (final s in copy.sources) s.name: standingAgainst(s.name)};

  @override
  int? landingsBetween({required Point from, required Point to}) => ordinal(to) - ordinal(from);

  @override
  Future<FunctionResult> run(String verb, {List<String> args = const []}) async {
    copy.runCalls.add((id, verb, args));
    return const FunctionResult(code: 0, out: '', err: '');
  }
}

/// The copy the place holds. Every call is recorded; every answer is seeded.
final class FakeCopy implements Copy {
  FakeCopy({required this.directory, required this.plot, required Manifest manifest, this.address}) : _manifest = manifest;

  @override
  final Directory directory;
  @override
  final Directory plot;
  Manifest _manifest;
  /// Seed: the copy refuses to read its own declaration (entity R2.5.3).
  String? manifestRefusal;
  @override
  Manifest get manifest => manifestRefusal == null ? _manifest : throw ManifestRefused(directory.path, manifestRefusal!);
  set manifest(Manifest m) => _manifest = m;
  final String? address;
  @override
  String get name => manifest.name;

  DateTime Function() clock = () => DateTime.now();
  int actCounter = 0;

  final Map<String, Known> known = {};
  final Map<String, Map<String, String>> files = {};
  final Map<String, int> tip = {};
  final Map<String, List<Action>> history = {};
  @override
  final List<Source> sources = [];
  @override
  final Map<String, Set<Directory>> materializations = {};

  // seeded answers
  /// standings[source][instance] — absent → unknown.
  final Map<String, Map<String, Standing>> standings = {};
  /// pastPoint[source][instance][point] — landings the source holds past a point.
  final Map<String, Map<String, Map<Point, int>>> pastPoint = {};
  final Map<String, Instant> contacted = {};
  final Set<String> unreachable = {};
  final Set<String> unfetchable = {};
  final Map<(String, String), MoveReport> moveAnswers = {};
  int moveUnderNext = 0;
  bool diverge = false;
  String? gateWords;

  // recorded calls
  final List<(String, Actor, String?)> actCalls = [];
  final List<(String, Actor, String?)> bornCalls = [];
  final List<(String, Directory, Point?)> materializeCalls = [];
  final List<Directory> releaseCalls = [];
  final List<(String, String, Direction)> moveCalls = [];
  final List<(String, String, Point?)> standingCalls = [];
  final List<(String, String?)> contactCalls = [];
  final List<(String, String, List<String>)> runCalls = [];

  Map<String, String> filesAt(String id, Point at) {
    final h = history[id] ?? const [];
    final n = ordinal(at);
    if (n == 0) return {};
    if (n > h.length) return files[id] ?? {};
    // The fake keeps one tree per landing: replay is the tree as of that landing.
    return _trees[id]?[n] ?? files[id] ?? {};
  }

  final Map<String, Map<int, Map<String, String>>> _trees = {};

  /// Every instance this copy knows to exist — here or at a source.
  @override
  List<Instance> get instances => [for (final id in known.keys) FakeInstance(this, id)];
  @override
  FakeInstance instance(String id) => FakeInstance(this, id);
  @override
  List<Instance> instancesAsOf(Instant when) =>
      [for (final k in known.values) if (k.born == null || !k.born!.isAfter(when)) FakeInstance(this, k.id)];

  @override
  void addSource(Source source) => sources.add(source);
  @override
  void changeSource(String name, {Set<Role>? roles, Cadence? cadence}) {
    final i = sources.indexWhere((s) => s.name == name);
    final s = sources[i];
    sources[i] = Source(name: name, address: s.address, roles: roles ?? s.roles, cadence: cadence ?? s.cadence);
  }
  @override
  void dropSource(String name) => sources.removeWhere((s) => s.name == name);
  @override
  void refit() {}

  final List<(Actor, String?)> classActs = [];
  @override
  Future<Outcome> actOnClass(FutureOr<void> Function(Act) body, {required Actor by, String? say}) async {
    classActs.add((by, say));
    final dir = Directory(p.join(plot.path, 'acts', 'class-${actCounter++}'))..createSync(recursive: true);
    final a = FakeAct(this, '.class', by, pt(0), dir);
    await body(a);
    a.abandon();
    return Landed(Action(point: pt(1), actor: by, when: clock(), say: say, title: null, arrivedFrom: null));
  }

  // events — nothing in the place's suite arms; recorded and inert.
  final List<Registration> armed = [];
  @override
  Registration arm(String command, {String? instance}) {
    final r = Registration(id: 'r${armed.length}', command: command, instance: instance, once: false);
    armed.add(r);
    return r;
  }
  @override
  Registration armOnce(String command, {String? instance}) {
    final r = Registration(id: 'r${armed.length}', command: command, instance: instance, once: true);
    armed.add(r);
    return r;
  }
  @override
  void disarm(String id) => armed.removeWhere((r) => r.id == id);
  @override
  Stream<Event> listen({String? instance}) => const Stream.empty();

  // flow
  @override
  Future<ContactReport> contact(String source, {Instance? about}) async {
    contactCalls.add((source, about?.id));
    if (unreachable.contains(source)) throw SourceUnreachable(_addressOf(source));
    contacted[source] = clock();
    return ContactReport(source: source, at: contacted[source]!, positions: {}, discovered: const []);
  }

  @override
  Future<MoveReport> move(Instance instance, {required String source, required Direction direction}) async {
    moveCalls.add((instance.id, source, direction));
    if (unreachable.contains(source)) return SourceOutOfReach(instance: instance.id, source: source, because: 'cut');
    return moveAnswers[(instance.id, source)] ?? NothingToCarry(instance: instance.id, source: source);
  }

  final List<(String, Direction)> moveClassCalls = [];
  @override
  Future<MoveReport> moveClass({required String source, required Direction direction}) async {
    moveClassCalls.add((source, direction));
    if (unreachable.contains(source)) return SourceOutOfReach(instance: '', source: source, because: 'cut');
    return NothingToCarry(instance: '', source: source);
  }

  String _addressOf(String source) => sources.firstWhere((s) => s.name == source).address;

  // presence
  @override
  Future<Materialization> materialize(Instance instance, {required Directory at, Point? point}) async {
    materializeCalls.add((instance.id, at, point));
    if (unfetchable.contains(instance.id)) throw ContentUnavailable(instance.id, tried: sources.map((s) => s.address).toList());
    materializations.putIfAbsent(instance.id, () => {}).add(at);
    refresh(instance.id);
    return Materialization(instance: instance.id, directory: at, point: point ?? this.instance(instance.id).here ?? pt(0), pinned: point != null);
  }

  @override
  Future<void> release(Directory at) async {
    releaseCalls.add(at);
    for (final s in materializations.values) {
      s.removeWhere((d) => d.path == at.path);
    }
    if (at.existsSync()) at.deleteSync(recursive: true);
  }

  /// The copy refreshes its own views on landing: files of [id] appear at
  /// every directory it stands materialized at.
  void refresh(String id) {
    final n = tip[id] ?? 0;
    if (n > 0) (_trees[id] ??= {})[n] = Map.of(files[id] ?? {});
    for (final dir in materializations[id] ?? const <Directory>{}) {
      Directory(dir.path).createSync(recursive: true);
      for (final e in (files[id] ?? const {}).entries) {
        File(p.join(dir.path, e.key))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(e.value);
      }
    }
  }
}

/// A far thing an address answers with.
final class FakeRemote {
  FakeRemote(this.manifest, {this.reachable = true, this.instances = const []});
  final Manifest manifest;
  bool reachable;
  final List<Seed> instances;
}

/// The gate: what the place calls to enter the entity.
final class FakeGate implements CopyGate {
  final Map<String, FakeRemote> remotes = {};
  final List<FakeCopy> copies = [];
  final List<(String, Directory, Directory)> standCalls = [];
  final List<String> manifestAtCalls = [];

  FakeCopy? copyAt(String path) {
    for (final c in copies) {
      if (c.directory.path == path) return c;
      for (final s in c.materializations.values) {
        if (s.any((d) => d.path == path)) return c;
      }
    }
    return null;
  }

  @override
  Future<Copy> stand(String address, {required Directory at, required Directory plot}) async {
    standCalls.add((address, at, plot));
    final r = remotes[address];
    if (r == null || !r.reachable) throw SourceUnreachable(address);
    final c = FakeCopy(directory: at, plot: plot, manifest: r.manifest, address: address);
    for (final s in r.instances) {
      c.known[s.id] = Known(s.id, title: s.title, contentHere: false, born: s.born);
    }
    c.sources.add(Source(name: 'hub', address: address, roles: r.manifest.rhythm.roles, cadence: r.manifest.rhythm.cadence));
    at.createSync(recursive: true);
    copies.add(c);
    return c;
  }

  @override
  Future<Copy> author(Manifest manifest, {required Directory at, required Directory plot, required Actor actor}) async {
    final c = FakeCopy(directory: at, plot: plot, manifest: manifest);
    at.createSync(recursive: true);
    copies.add(c);
    return c;
  }

  @override
  Copy at(Directory at, {required Directory plot}) {
    final c = copyAt(at.path);
    if (c == null) throw NotACopy(at);
    return c;
  }

  @override
  Future<Manifest> manifestAt(String address) async {
    manifestAtCalls.add(address);
    final r = remotes[address];
    if (r == null || !r.reachable) throw SourceUnreachable(address);
    return r.manifest;
  }
}
