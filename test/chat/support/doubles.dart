/// The two seams, doubled — a tree that really holds files and acts, and
/// bodies that really write into it.
///
/// Doubles rather than stubs on purpose: a suite whose fakes answer constants
/// asserts about its own fixtures. These carry the layout the contract names,
/// so every reading claim bites the moment a construction exists.
library;

import 'package:bentos_userland/bentos_chat.dart';

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

/// One invocation of a body.
final class BodyCall {
  const BodyCall(this.function, this.arguments, this.attempts);

  final String function;
  final List<String> arguments;

  /// The bound this call carried down — what the library set
  /// [attemptsVariable] to in the child's environment.
  final int attempts;
}

/// What a body does when it is run.
typedef BodyHandler = BodyOutcome Function(List<String> arguments, FakeTree tree);

/// The entity's embarked functions, doubled.
final class FakeBodies implements ChatBodies {
  FakeBodies(this.tree) {
    // The two functions the entity actually ships that write. They land real
    // acts, so a reading claim asserted after an act is asserted against a tree
    // an act really changed.
    handlers['join'] = (arguments, tree) {
      final display = _valueOf(arguments, '--name');
      final seat = '$participantsPath/${identity.handle.local}';
      final act = tree.land(
        noun: 'membership',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        writes: {
          '$seat/joined': '2026-08-06T12:00:00Z\n',
          if (display != null) '$seat/name': '$display\n',
        },
        sentence: 'join · ${identity.handle}',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
    // The gate every writing body but `join` asks, against the tree as it then
    // stands — a member is a seat, and a seat is a directory.
    BodyOutcome? refusedUnlessSeated(String function) {
      final seat = '$participantsPath/${identity.handle.local}';
      if (tree.files.keys.any((k) => k.startsWith('$seat/'))) return null;
      return BodyOutcome(
        exitCode: bodyRefused,
        stderr: '$function: refused — ${identity.handle} is not in '
            'bentos.chat:$channel (join first)',
      );
    }

    // Leaving tears the seat down whole and touches nothing else: what was said
    // stays said, because the roster and the transcript answer two different
    // questions.
    handlers['leave'] = (arguments, tree) {
      final refusal = refusedUnlessSeated('leave');
      if (refusal != null) return refusal;
      final act = tree.land(
        noun: 'membership',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        removes: ['$participantsPath/${identity.handle.local}'],
        sentence: 'leave · ${identity.handle}',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
    handlers['topic'] = (arguments, tree) {
      final refusal = refusedUnlessSeated('topic');
      if (refusal != null) return refusal;
      final act = tree.land(
        noun: 'topic',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        writes: {topicPath: '${arguments.first}\n'},
        sentence: 'topic · ${identity.handle} · "${arguments.first}"',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
    // The field EXISTS when the participant is away and its contents are the
    // reason, which may be empty — so a reason nobody gave is an empty file and
    // never a missing one.
    handlers['away'] = (arguments, tree) {
      final refusal = refusedUnlessSeated('away');
      if (refusal != null) return refusal;
      final act = tree.land(
        noun: 'presence',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        writes: {
          '$participantsPath/${identity.handle.local}/away':
              arguments.isEmpty ? '' : arguments.first,
        },
        sentence: 'away · ${identity.handle}',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
    handlers['back'] = (arguments, tree) {
      final refusal = refusedUnlessSeated('back');
      if (refusal != null) return refusal;
      final act = tree.land(
        noun: 'presence',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        removes: ['$participantsPath/${identity.handle.local}/away'],
        sentence: 'back · ${identity.handle}',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
    handlers['say'] = (arguments, tree) {
      final body = arguments.first;
      final refusal = refusedUnlessSeated('say');
      if (refusal != null) return refusal;
      final id = '01K${(tree.acts.length + 1).toString().padLeft(3, '0')}';
      final act = tree.land(
        noun: 'message',
        authorName: identity.displayName ?? '',
        authorEmail: identity.handle.email,
        writes: {
          '$messagesPath/2026/08/06/$id.md':
              'author: ${identity.displayName} <${identity.handle.email}>\n'
                  'spoken: ${(spokenTimes.isEmpty ? '2026-08-06T12:00:00Z' : spokenTimes.removeAt(0))}\n'
                  '\n$body\n',
        },
        sentence: 'say · ${identity.handle} · "$body"',
      );
      return BodyOutcome(exitCode: 0, stdout: act.commit);
    };
  }

  final FakeTree tree;
  final Map<String, BodyHandler> handlers = {};
  final List<BodyCall> calls = [];

  /// Who these bodies commit as. The bodies read git's own cascade; the double
  /// is told, because the seam under test is the library's and not git's.
  FakeIdentity identity = FakeIdentity();
  String channel = 'fabrica';

  /// Spoken times handed out in order, so a fixture can make the order of
  /// arrival and the order of the clock **disagree** — which is the only shape
  /// in which the transcript's ordering claim means anything.
  final List<String> spokenTimes = [];

  /// Makes [function] answer flatly, whatever it is asked.
  void answers(
    String function, {
    required int exitCode,
    String stdout = '',
    String stderr = '',
  }) =>
      handlers[function] = (_, _) =>
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
    final handler = handlers[function];
    if (handler == null) {
      return BodyOutcome(
        exitCode: 1,
        stderr: "entity run: bentos.chat declares no function '$function'",
      );
    }
    return handler(arguments, tree);
  }

  static String? _valueOf(List<String> arguments, String flag) {
    final at = arguments.indexOf(flag);
    return at < 0 || at + 1 >= arguments.length ? null : arguments[at + 1];
  }
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
