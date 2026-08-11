/// The two seams, filled against the real floor — the entity primitive for
/// reading, the entity's own embarked bodies for writing, and git's own cascade
/// for identity.
///
/// Nothing here is chat: it is the adaptation of one layout to one primitive,
/// which is exactly why it sits behind an interface. The channel above holds
/// the application's laws and never learns that a repository exists.
library;

import 'dart:convert';
import 'dart:io';

import '../entity/entity.dart';
import '../entity/instance.dart';
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

/// Runs the entity's own embarked functions, through the primitive.
///
/// `entity -C <place> run <coord> <function> [args]`, with the retry bound in
/// the child's environment — **the bound is the caller's and the loop is the
/// body's**, so nothing here waits, counts or tries again.
final class ProcessBodies implements ChatBodies {
  const ProcessBodies({
    required this.place,
    required this.coordinate,
    this.executable = 'entity',
  });

  /// The place the coordinate resolves from.
  final String place;

  /// `bentos.chat:<name>`.
  final String coordinate;

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

  /// Pins the commit's signer to **the same read** the body uses to declare
  /// the speaker, so the two can no longer be two facts that happen to agree.
  ///
  /// The body writes `--actor` to nobody: `entity commit` given none falls
  /// back to whatever `GIT_AUTHOR_*`/`GIT_COMMITTER_*` the ambient environment
  /// carries, which is a cascade the caller's own shell can pollute — a stale
  /// export, a CI harness simulating participants by variable rather than by
  /// config — and disagrees with `git config`, which is what the identity
  /// written into the content is read from. Setting those variables here,
  /// from this same [GitIdentity] read, forces every hop underneath (the
  /// body, and the `entity commit` it shells out to in turn) to sign under
  /// exactly what was declared, whatever else the environment carries — an
  /// explicit override always wins over an inherited one.
  ///
  /// Empty when git has no identity to speak under at all: the write then
  /// refuses downstream exactly as it always did, and inventing one here
  /// would be putting words in nobody's mouth.
  Map<String, String> _signerEnvironment() {
    final Identity identity;
    try {
      identity = GitIdentity.of(Entity(chatOntology, from: place));
    } on NoIdentity {
      return const {};
    }
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

/// Who the caller is, from **the cascade the commit will be signed under** —
/// the entity's own repository, never the directory the caller happens to be
/// standing in. Asking the working directory would answer for whatever
/// repository the caller is inside, which is a different substrate.
///
/// It mirrors `lib.sh`'s own `_identity`, deliberately: two readers of the
/// same cascade, both `git config` and neither the ambient environment — which
/// is exactly why [ProcessBodies] does not stop at reading this and stating
/// it, but hands it back down as the explicit signer for every body it runs.
final class GitIdentity implements Identity {
  GitIdentity._(this.handle, this.displayName);

  /// Reads the cascade of [entity]'s repository.
  factory GitIdentity.of(Entity entity) {
    final gitDir = gitDirOf(entity);
    final email = _config(gitDir, 'user.email');
    if (email == null || email.isEmpty) throw NoIdentity(gitDir);
    final name = _config(gitDir, 'user.name');
    return GitIdentity._(
      Handle.ofEmail(email),
      name == null || name.isEmpty ? null : name,
    );
  }

  @override
  final Handle handle;

  @override
  final String? displayName;

  static String? _config(String gitDir, String key) {
    final result = Process.runSync('git', ['-C', gitDir, 'config', key]);
    if (result.exitCode != 0) return null;
    return '${result.stdout}'.trim();
  }
}
