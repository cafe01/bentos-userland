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
            authorEmail: action.actor.email,
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

/// Opens the act bracket **in process**, through [Instance.materialize] and
/// [Instance.act] — no shell, no spawn, no private area: the tree the gate
/// reads and the tree the act commits in are the same one, attached.
///
/// **What this seam no longer has, and deliberately.** The retired path
/// opened a private area per attempt and landed it by compare-and-swap, so
/// two attempts racing the same tip produced one [Landed] and one
/// [ChatContested] — a value [LocalChannel] retried on. `act` now commits
/// where the instance already stands: one attached tree per instance, no
/// swap, and therefore no detection of two actors landing in the same
/// instant. The race did not go away — a channel is many actors on one
/// instance, so chat is the surface that most feels the cost — only the
/// compare-and-swap that used to *report* it did, ruled out of the act path
/// on purpose and kept for one job alone: an instance's birth. [LocalChannel]'s
/// retry loop is left standing on [ChatContested] rather than gutted, because
/// silently removing it is a chat-behaviour decision this seam does not own;
/// it simply cannot fire through this implementation any longer.
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

  /// **Guarded at the primitive**, not here: [Instance.ensureBorn] swaps the ref
  /// from nothing under compare-and-swap, so four beings joining an unborn
  /// channel at one instant birth it once and the three that lost the swap
  /// simply find it born. Read-then-create in this file could only ever widen
  /// the gap it was trying to close, and a birth race is a fact about every
  /// entity an external will enters through — never about chat.
  @override
  void ensureBorn() {
    instance.ensureBorn();
  }

  @override
  Future<ChatActOutcome> attempt(
    String noun, {
    required void Function(ChatArea area) write,
    String? Function(ChatArea area)? gate,
    String? say,
  }) async {
    // The gate reads the standing tree **before** act is entered — nothing it
    // asks needs the bracket, since under the retired law the private area
    // was the only place a fresh-cut tip could be read from, and under this
    // one the attached tree already *is* that reading. A refusal here lands
    // nothing and opens no act.
    final standing = instance.materialize();
    final refusal = gate?.call(_MaterializedArea(standing.directory));
    if (refusal != null) return ChatGateRefused(refusal);
    final actor = Actor(identity.displayName, email: identity.handle.email);
    final result = await instance.act(
      noun,
      (area) => write(_MaterializedArea(area.directory)),
      actor: actor,
      say: say,
    );
    switch (result) {
      case Landed(:final action):
        return ChatLanded(action.commit.sha);
      case Barred(:final reason):
        return ChatGateRefused(reason);
      case Contested():
        // Unreachable: `act` commits where the instance already stands, and
        // there is no swap left to lose. Mirrors [Diverged] below rather than
        // returning a value nothing here can produce.
        throw StateError(
            '$chatOntology: an act contested, which a local act never does '
            'now that it commits in the instance\'s own attached tree');
      case Diverged():
        // Only [Instance.fetch] can diverge; a local act never does.
        throw StateError('$chatOntology: an act diverged, which a local act never does');
    }
  }
}

/// [ChatArea] over a real materialized directory — ordinary file IO, and
/// nothing else. The primitive never looks at what is written here; it only
/// hashes the tree once [Instance.act] commits.
final class _MaterializedArea implements ChatArea {
  _MaterializedArea(this._directory);

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

  @override
  String? read(String path) {
    final file = File(_resolve(path));
    return file.existsSync() ? file.readAsStringSync() : null;
  }
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
    final name = identity.displayName;
    final email = identity.handle.email;
    return {
      'GIT_AUTHOR_NAME': name,
      'GIT_AUTHOR_EMAIL': email,
      'GIT_COMMITTER_NAME': name,
      'GIT_COMMITTER_EMAIL': email,
    };
  }
}

/// Who the calling process speaks as — the one seam every face shares.
///
/// **Three sources, all of them the caller's own word, and then a refusal.** An
/// explicit [identity] wins outright, the seam a caller or a test injects
/// through directly. Then [stated], what the caller said in argv — ahead of the
/// environment, because a face that can only be told who is speaking through a
/// variable is not scriptable, and a mind reaching this program through a tool
/// has argv and no shell to export from. Then `$BENTOS_CHAT_IDENTITY`, chat's
/// own variable, a value somebody set deliberately at launch and never
/// something that describes the machine.
///
/// > The refusal fires on **silence, from any caller whatever**.
///
/// Not on a guess about who is asking. A caller that declares itself a being of
/// the kind and a caller that declares nothing get the same answer, and the
/// second one is the case that matters: it is the caller that must be refused,
/// and it was the one being served. No property of the caller may soften it —
/// not plausibility, not resemblance to a known participant, not a perfectly
/// good address sitting one directory away in a git config.
///
/// Nothing on the machine may answer. Not the entity's `repo.git`, not the
/// user's git configuration, not a chat configuration file of our own: a file
/// that answers for a caller who said nothing is the cascade again with better
/// manners, and one installation serves many beings.
Identity resolveChatIdentity({
  Identity? identity,
  String? stated,
  Map<String, String>? environment,
}) {
  if (identity != null) return identity;
  final env = environment ?? Platform.environment;
  final value = (stated != null && stated.isNotEmpty)
      ? stated
      : env[identityVariable];
  if (value == null || value.isEmpty) throw const NoIdentity(statedIdentityForm);
  return parseStatedIdentity(value);
}

/// Where a caller states who is speaking when it does not say so in argv.
const String identityVariable = 'BENTOS_CHAT_IDENTITY';

/// The whole diagnostic, and therefore the whole of the ergonomics: it is what
/// a mind reads on its first refusal, so it prints the flag, the variable and
/// the form in one sentence, with no advice about who the caller might be.
const String statedIdentityForm =
    'say who you are: --identity "Name <addr>", or \$$identityVariable set to '
    'the same. Both halves are required, and nothing else may answer — an '
    'identity is stated, never derived from the machine.';

/// A stated identity as both the argument and the variable spell it:
/// `Name <addr>`, and nothing else.
///
/// **A bare address is refused, and so is a bare name.** The floor requires a
/// name and an address; accepting half and filling the rest with an empty
/// string is how a blank name reached a commit, and synthesizing an address
/// from a name is how a plausible one would.
Identity parseStatedIdentity(String stated) {
  final trimmed = stated.trim();
  final match = RegExp(r'^(.*)<([^<>]+)>$').firstMatch(trimmed);
  if (match == null) throw const NoIdentity(statedIdentityForm);
  final name = match.group(1)!.trim();
  final email = match.group(2)!.trim();
  if (name.isEmpty) {
    throw const NoIdentity('an address with no name — $statedIdentityForm');
  }
  if (email.isEmpty || !email.contains('@')) {
    throw const NoIdentity('a name with no address — $statedIdentityForm');
  }
  return _StatedIdentity(Handle.ofEmail(email), name);
}

final class _StatedIdentity implements Identity {
  const _StatedIdentity(this.handle, this.displayName);

  @override
  final Handle handle;

  @override
  final String displayName;
}
