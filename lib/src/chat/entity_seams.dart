/// The two seams, filled against the real floor — the entity primitive for
/// reading and for the in-process act bracket, `check` alone still spawning
/// the entity's own embarked function, and [resolveChatIdentity] for who is
/// speaking.
///
/// Nothing here is chat: it is the adaptation of one layout to one primitive,
/// which is exactly why it sits behind an interface. The channel above holds
/// the application's laws and never learns that a repository exists.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity/action.dart';
import '../entity/instance.dart';
import '../git/model/actor.dart';
import '../git/model/commit.dart';
import 'handle.dart';
import 'ontology.dart';
import 'seams.dart';

/// Reads a channel through the primitive, **in process**: a spawn per read
/// makes a live face unusable, which is the whole reason this half is not a
/// process at all.
final class EntityTree implements ChatTree {
  EntityTree(this.instance);

  /// The channel's instance — `bentos.chat:<name>`.
  final Instance instance;

  @override
  String? tip() => instance.tip?.sha;

  @override
  String? read(String path, {String? at}) {
    if (at == null && instance.tip == null) return null;
    try {
      return utf8.decode(
        instance.read(path, at: at == null ? null : Commit(at)),
        allowMalformed: true,
      );
    } on Object {
      // A path that is not in the tree is ordinary: a participant who declared
      // no display name simply has no such file, and the reader asks the path
      // rather than the bytes.
      return null;
    }
  }

  /// The primitive answers with paths from the root; the layout above speaks in
  /// entries under a directory. **Normalizing is this seam's job** — it is the
  /// one place that knows both vocabularies.
  @override
  List<String> ls(String path, {String? at}) {
    if (at == null && instance.tip == null) return const [];
    final listing = instance.ls(path, at: at == null ? null : Commit(at));
    final prefix = path.endsWith('/') ? path : '$path/';
    return [
      for (final entry in listing)
        entry.startsWith(prefix) ? entry.substring(prefix.length) : entry,
    ]..sort();
  }

  @override
  List<ChatAct> log() => [
        for (final action in instance.log())
          ChatAct(
            commit: action.commit.sha,
            noun: action.name,
            authorName: action.actor.name,
            authorEmail: action.actor.email ?? '',
            instant: action.instant,
            sentence: action.sentence,
          ),
      ];

  @override
  List<String> added(String commit) {
    for (final action in instance.log()) {
      if (action.commit.sha != commit) continue;
      return [
        for (final change in action.diff().changes)
          if (change.kind == ChangeKind.added) change.path,
      ]..sort();
    }
    return const [];
  }
}

/// Opens the act bracket **in process**, through [Instance.beginAct] and
/// [Workspace.commit] — no shell, no spawn. One attempt per call; the retry
/// loop is [LocalChannel]'s, never this seam's.
final class EntityActs implements ChatActs {
  EntityActs(this.instance, {required this.identity});

  final Instance instance;

  /// Who commits. Passed **explicitly** to every commit rather than left to
  /// the ambient environment — [ProcessBodies] learned this the hard way: a
  /// caller's own shell can carry a stale `GIT_AUTHOR_*` export, and
  /// `commit-tree` prefers it over the repository's own configured identity.
  /// Stating the signer here, from the same cascade [identity] was read from,
  /// forces every act to sign under exactly what was declared.
  final Identity identity;

  @override
  bool get born => instance.tip != null;

  @override
  void ensureBorn() {
    if (!born) instance.create();
  }

  @override
  ChatActOutcome attempt(
    String noun, {
    required void Function(ChatArea area) write,
    String? Function(ChatArea area)? gate,
    String? say,
  }) {
    final workspace = instance.beginAct();
    try {
      final area = _WorkspaceArea(workspace.directory);
      final refusal = gate?.call(area);
      if (refusal != null) return ChatGateRefused(refusal);
      write(area);
      final actor = Actor(
        identity.displayName ?? identity.handle.local,
        email: identity.handle.email,
      );
      final result = workspace.commit(noun, actor: actor, say: say);
      switch (result) {
        case Landed(:final action):
          return ChatLanded(action.commit.sha);
        case Barred(:final reason):
          return ChatGateRefused(reason);
        case Contested():
          return const ChatContested();
        case Diverged():
          // Only [Instance.fetch] can diverge; a local act never does.
          throw StateError('$chatOntology: an act diverged, which a local act never does');
      }
    } finally {
      workspace.release();
    }
  }
}

/// [ChatArea] over a real materialized directory — ordinary file IO, and
/// nothing else. The primitive never looks at what is written here; it only
/// hashes the tree once [Workspace.commit] is asked.
final class _WorkspaceArea implements ChatArea {
  _WorkspaceArea(this._directory);

  final Directory _directory;

  String _resolve(String path) => p.join(_directory.path, path);

  @override
  void write(String path, String content) {
    final file = File(_resolve(path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  @override
  void removeTree(String path) {
    final full = _resolve(path);
    final type = FileSystemEntity.typeSync(full);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      Directory(full).deleteSync(recursive: true);
    } else {
      File(full).deleteSync();
    }
  }

  @override
  bool exists(String path) =>
      FileSystemEntity.typeSync(_resolve(path)) != FileSystemEntityType.notFound;
}

/// Runs the entity's own embarked functions, through the primitive — kept for
/// `check` alone, which is not a [Channel] method and has no [ChatActs]
/// bracket to open.
///
/// `entity -C <place> run <coord> <function> [args]`, with the retry bound in
/// the child's environment — **the bound is the caller's and the loop is the
/// body's**, so nothing here waits, counts or tries again.
final class ProcessBodies implements ChatBodies {
  const ProcessBodies({
    required this.place,
    required this.coordinate,
    required this.identity,
    this.executable = 'entity',
  });

  /// The place the coordinate resolves from.
  final String place;

  /// `bentos.chat:<name>`.
  final String coordinate;

  /// Who runs this — resolved once, the same way [EntityFloor.channel]
  /// resolves it, and handed in rather than re-derived here.
  final Identity identity;

  /// The primitive on the PATH. Named rather than assumed, so a gate can drive
  /// a build that is not the installed one.
  final String executable;

  @override
  Future<BodyOutcome> run(
    String function,
    List<String> arguments, {
    required int attempts,
  }) async {
    final result = await Process.run(
      executable,
      ['-C', place, 'run', coordinate, function, ...arguments],
      environment: {attemptsVariable: '$attempts', ..._signerEnvironment()},
    );
    return BodyOutcome(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  /// Pins the commit's signer to **the same [identity]** the caller resolved,
  /// so the two can no longer be two facts that happen to agree.
  ///
  /// The body writes `--actor` to nobody: `entity commit` given none falls
  /// back to whatever `GIT_AUTHOR_*`/`GIT_COMMITTER_*` the ambient environment
  /// carries, which is a cascade the caller's own shell can pollute — a stale
  /// export, a CI harness simulating participants by variable rather than by
  /// config. Setting those variables here, from this same [identity], forces
  /// every hop underneath (the body, and the `entity commit` it shells out to
  /// in turn) to sign under exactly what was declared, whatever else the
  /// environment carries — an explicit override always wins over an inherited
  /// one.
  Map<String, String> _signerEnvironment() {
    final name = identity.displayName ?? '';
    final email = identity.handle.email;
    return {
      'GIT_AUTHOR_NAME': name,
      'GIT_AUTHOR_EMAIL': email,
      'GIT_COMMITTER_NAME': name,
      'GIT_COMMITTER_EMAIL': email,
    };
  }
}

/// Who the calling process speaks as — the one seam both faces share.
///
/// Order: an explicit [identity] wins outright — the seam a caller or a test
/// injects through directly. Absent that, `$BENTOS_CHAT_IDENTITY` is the
/// stated override, `Name <email>` or a bare email: how a human testing as
/// someone else, or a being of the kind stating its own voice, both speak.
/// Absent that: `$BENTOS_AGENT` set means the caller **is** a being, and a
/// being that has not stated an identity is a question, never a default —
/// refusing rather than borrowing the ambient git cascade of whatever human
/// owns the machine it happens to run on, which would be impersonation, not a
/// fallback. `$BENTOS_AGENT` unset means an ordinary human at their own
/// keyboard, and their ambient git cascade **is** their identity.
///
/// Frontier, not settled: a being's identity has nowhere else to live today
/// but this one chat-scoped variable. No manifest, no entity, nothing beside
/// a being's own bank currently publishes it — closing that gap properly
/// means the being states itself once, not per chat session.
Identity resolveChatIdentity({
  Identity? identity,
  Map<String, String>? environment,
}) {
  if (identity != null) return identity;
  final env = environment ?? Platform.environment;
  final stated = env['BENTOS_CHAT_IDENTITY'];
  if (stated != null && stated.isNotEmpty) return _parseStatedIdentity(stated);
  final agent = env['BENTOS_AGENT'];
  if (agent != null && agent.isNotEmpty) {
    throw NoIdentity(
      'a being of the kind states its own identity — set '
      r'$BENTOS_CHAT_IDENTITY ("Name <email>" or a bare email); '
      '\$BENTOS_AGENT=$agent names no address on its own',
    );
  }
  return GitIdentity.ambient();
}

Identity _parseStatedIdentity(String stated) {
  final trimmed = stated.trim();
  final match = RegExp(r'^(.*)<(.+)>$').firstMatch(trimmed);
  if (match == null) {
    return _StatedIdentity(Handle.ofEmail(trimmed), null);
  }
  final name = match.group(1)!.trim();
  final email = match.group(2)!.trim();
  return _StatedIdentity(Handle.ofEmail(email), name.isEmpty ? null : name);
}

final class _StatedIdentity implements Identity {
  const _StatedIdentity(this.handle, this.displayName);

  @override
  final Handle handle;

  @override
  final String? displayName;
}

/// A human's own git cascade — global config, or whatever local repository
/// the process actually stands in. **Never the medium's repository**: the
/// entity a channel lives in is the substrate a message is written to, not
/// the identity of whoever is writing it, and reading the two from the same
/// place is what let one process's `git config` answer for every caller who
/// ever touched that installation.
final class GitIdentity implements Identity {
  GitIdentity._(this.handle, this.displayName);

  /// Reads the caller's own ambient cascade — no `-C`, so it is whatever
  /// directory the process is actually running in.
  factory GitIdentity.ambient() {
    final email = _config('user.email');
    if (email == null || email.isEmpty) {
      throw const NoIdentity(
        'no user.email in the ambient git cascade — git has no identity to '
        'speak under',
      );
    }
    final name = _config('user.name');
    return GitIdentity._(
      Handle.ofEmail(email),
      name == null || name.isEmpty ? null : name,
    );
  }

  @override
  final Handle handle;

  @override
  final String? displayName;

  static String? _config(String key) {
    final result = Process.runSync('git', ['config', key]);
    if (result.exitCode != 0) return null;
    return '${result.stdout}'.trim();
  }
}
