/// The two seams, doubled — a tree that really holds files and acts, and
/// bodies that really write into it.
///
/// Doubles rather than stubs on purpose: a suite whose fakes answer constants
/// asserts about its own fixtures. These carry the layout the contract names,
/// so every reading claim bites the moment a construction exists.
library;

import 'dart:async';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/chat_client.dart' show Ticker;

/// A channel's substrate: files, and the acts that put them there.
final class FakeTree implements ChatTree {
  /// The files as they stand now.
  final Map<String, String> files = {};

  /// What the files were at each commit — because every read here answers **at
  /// a point in history**, and a fake that only knows the present cannot tell a
  /// reader that asked for the parent from one that did not.
  final Map<String, Map<String, String>> snapshots = {};

  /// Oldest first. [log] hands them back the way the substrate does.
  final List<ChatAct> acts = [];

  final Map<String, List<String>> _added = {};

  /// Every `at` this tree was asked for, in order — so a claim about reading at
  /// the parent is checkable rather than assumed.
  final List<String?> readsAt = [];

  bool logRead = false;

  String? _head;

  /// Lands an act, snapshotting the tree as it then stood.
  ChatAct land({
    required String noun,
    required String authorName,
    required String authorEmail,
    DateTime? instant,
    String? sentence,
    Map<String, String> writes = const {},
    List<String> removes = const [],
  }) {
    files.addAll(writes);
    for (final path in removes) {
      files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    }
    final commit = 'c${acts.length + 1}'.padRight(7, '0');
    final act = ChatAct(
      commit: commit,
      noun: noun,
      authorName: authorName,
      authorEmail: authorEmail,
      instant: instant ?? DateTime.utc(2026, 8, 6, 12, acts.length),
      sentence: sentence,
    );
    acts.add(act);
    _added[commit] = writes.keys.toList()..sort();
    snapshots[commit] = Map.of(files);
    _head = commit;
    return act;
  }

  /// Nobody has opened this channel.
  void unborn() {
    files.clear();
    acts.clear();
    _head = null;
  }

  /// Births the ref at an empty structure, with no act of its own — mirroring
  /// `Instance.create()`: [tip] answers non-null and [log] stays empty until
  /// the first act lands.
  void birth() => _head ??= 'genesis-tip';

  @override
  String? tip() => _head;

  @override
  String? read(String path, {String? at}) {
    readsAt.add(at);
    final where = at == null ? files : (snapshots[at] ?? const {});
    return where[path];
  }

  @override
  List<String> ls(String path, {String? at}) {
    readsAt.add(at);
    final where = at == null ? files : (snapshots[at] ?? const {});
    final prefix = '$path/';
    final under = <String>{};
    for (final key in where.keys) {
      if (!key.startsWith(prefix)) continue;
      final rest = key.substring(prefix.length);
      final slash = rest.indexOf('/');
      under.add(slash < 0 ? rest : '${rest.substring(0, slash)}/');
    }
    return under.toList()..sort();
  }

  @override
  List<ChatAct> log() {
    logRead = true;
    return acts.reversed.toList();
  }

  @override
  List<String> added(String commit) => _added[commit] ?? const [];
}

/// The area one [FakeActs.attempt] writes into — a plain map, snapshotted from
/// the tree at the attempt's start so a gate and a writer see the same world a
/// real materialized worktree would hand them.
final class _FakeArea implements ChatArea {
  _FakeArea(Map<String, String> base) : files = Map.of(base);

  final Map<String, String> files;
  final Set<String> removed = {};

  @override
  void write(String path, String content) {
    files[path] = content;
    removed.remove(path);
  }

  @override
  void removeTree(String path) {
    files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    removed.add(path);
  }

  @override
  bool exists(String path) =>
      files.keys.any((key) => key == path || key.startsWith('$path/'));
}

/// One attempt at an act, captured whole — so a fixture can prove the loop's
/// own shape: how many attempts it took, and with what.
final class ActAttempt {
  const ActAttempt(this.noun, this.gateCalled);

  final String noun;

  /// Whether [ChatActs.attempt]'s own `gate` argument was actually invoked on
  /// this attempt — not whether one was supplied. A contested or barred
  /// attempt pays for the gate exactly like a landing one does: the real
  /// floor cannot know either outcome until after it asked.
  final bool gateCalled;
}

/// The in-process act bracket, doubled over a [FakeTree] — the seam
/// [LocalChannel] now opens itself, with no shell and no spawn behind it.
final class FakeActs implements ChatActs {
  FakeActs(this.tree);

  final FakeTree tree;

  /// Who these acts commit as. The real seam reads git's own cascade; the
  /// double is told, because the seam under test is the library's and not
  /// git's.
  Identity identity = FakeIdentity();
  String channel = 'fabrica';

  /// Every attempt made, in order — so a fixture can prove the retry loop's
  /// own shape rather than merely its outcome.
  final List<ActAttempt> attempts = [];

  /// Forces the next [count] attempts at [noun] to answer [ChatContested] —
  /// the fixture that proves the caller's loop retries, and counts.
  void contestNext(String noun, int count) => _contests[noun] = count;
  final Map<String, int> _contests = {};

  /// Forces the next attempt at [noun] to answer [ChatGateRefused], whatever
  /// the real gate would have said — for the one shape the membership gate
  /// itself cannot produce: a floor-level refusal unrelated to a seat.
  void barNext(String noun, String reason) => _bars[noun] = reason;
  final Map<String, String> _bars = {};

  List<ActAttempt> attemptsAt(String noun) =>
      attempts.where((a) => a.noun == noun).toList();

  @override
  bool get born => tree.tip() != null;

  @override
  void ensureBorn() {
    if (!born) tree.birth();
  }

  @override
  ChatActOutcome attempt(
    String noun, {
    required void Function(ChatArea area) write,
    String? Function(ChatArea area)? gate,
    String? say,
  }) {
    if (!born) {
      throw StateError('not born: $chatOntology:$channel');
    }

    // The real floor pays this on every attempt, win or lose: a fresh area
    // materialized from the tip, the gate asked of it, the write run — only
    // then can it learn whether the swap landed, was contested, or was
    // barred. A double that answers Contested or Barred before any of that
    // is cheaper than the world in exactly the place the world is expensive,
    // which makes it no witness at all.
    final area = _FakeArea(tree.files);
    var gateCalled = false;
    String? refusal;
    if (gate != null) {
      gateCalled = true;
      refusal = gate(area);
    }
    attempts.add(ActAttempt(noun, gateCalled));
    if (refusal != null) return ChatGateRefused(refusal);
    write(area);

    final left = _contests[noun] ?? 0;
    if (left > 0) {
      _contests[noun] = left - 1;
      return const ChatContested();
    }
    final barred = _bars.remove(noun);
    if (barred != null) return ChatGateRefused(barred);

    final delta = <String, String>{
      for (final entry in area.files.entries)
        if (tree.files[entry.key] != entry.value) entry.key: entry.value,
    };
    final act = tree.land(
      noun: noun,
      authorName: identity.displayName ?? '',
      authorEmail: identity.handle.email,
      writes: delta,
      removes: area.removed.toList(),
      sentence: say,
    );
    return ChatLanded(act.commit);
  }
}

/// One invocation of a body.
final class BodyCall {
  const BodyCall(this.function, this.arguments, this.attempts);

  final String function;
  final List<String> arguments;
  final int attempts;
}

/// The entity's own declared functions, doubled — `check` alone runs through
/// this seam now, since it carries no seat and is not a [Channel] method.
final class FakeBodies implements ChatBodies {
  FakeBodies(this.tree);

  final FakeTree tree;
  final List<BodyCall> calls = [];
  final Map<String, BodyOutcome> _answers = {};

  /// Makes [function] answer flatly, whatever it is asked.
  void answers(
    String function, {
    required int exitCode,
    String stdout = '',
    String stderr = '',
  }) =>
      _answers[function] =
          BodyOutcome(exitCode: exitCode, stdout: stdout, stderr: stderr);

  List<BodyCall> callsTo(String function) =>
      calls.where((c) => c.function == function).toList();

  @override
  Future<BodyOutcome> run(
    String function,
    List<String> arguments, {
    required int attempts,
  }) async {
    calls.add(BodyCall(function, arguments, attempts));
    return _answers[function] ?? const BodyOutcome(exitCode: 0);
  }
}

/// A doorbell a test can ring by hand: [tick] fires one, and nothing else
/// ever does — the fixture that proves [Channel.wait] answers to the ticker
/// and not to a hidden cadence.
final class FakeTicker implements Ticker {
  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get ticks => _controller.stream;

  void tick() => _controller.add(null);

  @override
  void nudge() => tick();

  @override
  bool connected = true;

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}

/// The wall clock, doubled — one reading handed out per call, so a fixture
/// can make the order of arrival and the order of the clock **disagree**,
/// which is the only shape in which the transcript's ordering claim means
/// anything. Falls back to a fixed instant once the queue runs dry.
final class FakeClock {
  final List<DateTime> _queue = [];
  DateTime fallback = DateTime.utc(2026, 8, 6, 12);

  void push(DateTime instant) => _queue.add(instant);

  DateTime call() => _queue.isEmpty ? fallback : _queue.removeAt(0);
}

final class FakeIdentity implements Identity {
  FakeIdentity({
    this.handle = const Handle('alfred', 'bentos.life'),
    this.displayName = 'Alfred',
  });

  @override
  Handle handle;

  @override
  String? displayName;
}
