import 'dart:convert';
import 'dart:io';

import 'model/actor.dart';
import 'model/commit.dart';
import 'model/remote.dart';
import 'git.dart';

/// The real port: `git` as a subprocess.
///
/// **Construction's file.** Every body here is the design's declared contract
/// and the construction chair's labour; what design owed was the seam, the
/// verbs and the laws they must obey, and that is what the abstract [Git]
/// carries. The skeleton stands so the shape of the implementation is fixed
/// before a line of it is written.
///
/// Three laws bind whoever fills these in.
///
/// **The process name lives here and nowhere else.** The entity package's seam
/// guard asserts it: any other file that spells the executable has gone behind
/// the port, and the hermeticity of every test above it is void.
///
/// **The last step of an action is plumbing.** `git commit` reads the tip when
/// it runs and commits onto whatever it finds; the act needs the opposite, so
/// [writeTree], [commitTree] and [updateRef] stay separate verbs and the
/// expected value is carried through all three.
///
/// **The environment is not inherited into children.** A ref update running
/// under a hook exports `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`,
/// `GIT_OBJECT_DIRECTORY` and `GIT_QUARANTINE_PATH`; a child that inherits them
/// writes into the wrong repository, and the failure is silent.
final class ProcessGit implements Git {
  const ProcessGit();

  /// The executable. The one literal, and the reason the guard has a target to
  /// point at.
  static const String executable = 'git';

  /// The variables a hook exports into its children. Every invocation is told
  /// where to work by argument, so any one of these surviving in the
  /// environment can only be a lie waiting to be believed.
  static const List<String> _poisoned = [
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY',
    'GIT_QUARANTINE_PATH',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_COMMON_DIR',
    'GIT_PREFIX',
  ];

  // ---------------------------------------------------------------- the wire

  /// One invocation, with the environment scrubbed and the output taken as
  /// bytes — text is a decoding of a result, never the result itself.
  ProcessResult _run(
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) {
    final env = <String, String>{
      for (final e in Platform.environment.entries)
        if (!_poisoned.contains(e.key)) e.key: e.value,
      ...environment,
    };
    return Process.runSync(
      executable,
      arguments,
      environment: env,
      includeParentEnvironment: false,
      workingDirectory: workingDirectory,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
  }

  /// An invocation that must succeed. A non-zero exit is a fault of ours — a
  /// wrong path, a malformed object — and never an ordinary outcome; the one
  /// verb where refusal *is* ordinary reads the code itself.
  String _git(
    String gitDir,
    List<String> arguments, {
    Map<String, String> environment = const {},
  }) {
    final result = _run(
      ['--git-dir=$gitDir', ...arguments],
      environment: environment,
    );
    if (result.exitCode != 0) throw _failure(arguments, result);
    return _text(result.stdout).trimRight();
  }

  Future<String> _gitAsync(
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final env = <String, String>{
      for (final e in Platform.environment.entries)
        if (!_poisoned.contains(e.key)) e.key: e.value,
    };
    final result = await Process.run(
      executable,
      arguments,
      environment: env,
      includeParentEnvironment: false,
      workingDirectory: workingDirectory,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) throw _failure(arguments, result);
    return _text(result.stdout).trimRight();
  }

  static String _text(Object? raw) =>
      raw is List<int> ? utf8.decode(raw, allowMalformed: true) : '$raw';

  static ProcessException _failure(List<String> arguments, ProcessResult r) =>
      ProcessException(
        executable,
        arguments,
        _text(r.stderr).trim(),
        r.exitCode,
      );

  /// The identity the substrate is given, stated whole by whoever acted.
  ///
  /// **Both variables are always set, and nothing is derived here.** Git's own
  /// cascade — repository config, then global, then system — describes whoever
  /// owns a source checkout on this machine, and it answers a question nobody
  /// asked it: one installation serves many beings, and a commit signed from
  /// that position is a signed lie rather than a missing field. Leaving the
  /// environment empty is what let it answer, so the environment is never left
  /// empty; an act with nobody behind it is refused a floor above, where the
  /// caller is written.
  static Map<String, String> _identity(Actor actor) => {
        'GIT_AUTHOR_NAME': actor.name,
        'GIT_AUTHOR_EMAIL': actor.email,
        'GIT_COMMITTER_NAME': actor.name,
        'GIT_COMMITTER_EMAIL': actor.email,
      };

  // ------------------------------------------------------------- the repository

  @override
  void init(String gitDir, {bool bare = true}) {
    Directory(gitDir).createSync(recursive: true);
    final result = _run([
      'init',
      if (bare) '--bare',
      '--quiet',
      gitDir,
    ]);
    if (result.exitCode != 0) throw _failure(const ['init'], result);
  }

  // ------------------------------------------------------------------ objects

  @override
  String hashObject(String gitDir, List<int> bytes) {
    // `hash-object` reads stdin, and a synchronous spawn has none — so the
    // bytes travel by file. The temporary is ours and dies with the call.
    final scratch = Directory.systemTemp.createTempSync('entity-blob-');
    try {
      final file = File('${scratch.path}/blob')..writeAsBytesSync(bytes);
      return _git(gitDir, ['hash-object', '-w', '--no-filters', '--', file.path]);
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  @override
  List<int> catFile(String gitDir, String object) {
    final result = _run(['--git-dir=$gitDir', 'cat-file', '-p', object]);
    if (result.exitCode != 0) {
      throw _failure(['cat-file', '-p', object], result);
    }
    final out = result.stdout;
    return out is List<int> ? out : utf8.encode('$out');
  }

  @override
  List<String> lsTree(
    String gitDir, {
    required Commit at,
    required String path,
  }) {
    final result = _run([
      '--git-dir=$gitDir',
      'ls-tree',
      '--name-only',
      at.sha,
      '--',
      // The trailing slash is what asks for the entries *inside*: a bare
      // `messages` names the tree entry itself, and the listing would answer
      // with the directory it was asked to look in.
      if (path.isNotEmpty) (path.endsWith('/') ? path : '$path/'),
    ]);
    // A path that is not in the tree is not an error: the honest answer to
    // *what is under here* is that nothing is.
    if (result.exitCode != 0) return const [];
    return _lines(_text(result.stdout))..sort();
  }

  @override
  bool isAncestor(
    String gitDir, {
    required Commit ancestor,
    required Commit descendant,
  }) {
    final result = _run([
      '--git-dir=$gitDir',
      'merge-base',
      '--is-ancestor',
      ancestor.sha,
      descendant.sha,
    ]);
    // 0 and 1 are the answer; anything else is the substrate failing to
    // answer at all — an unknown object, most often — and must not be read
    // as *no*.
    if (result.exitCode > 1) {
      throw _failure(const ['merge-base', '--is-ancestor'], result);
    }
    return result.exitCode == 0;
  }

  @override
  String writeTree(String gitDir, {required String workTree}) {
    // The staging is folded in: *the tree of this worktree* is one idea, and
    // the index it needs is a detail of the substrate — so it is a scratch file
    // nobody above this line ever hears about.
    final scratch = Directory.systemTemp.createTempSync('entity-index-');
    try {
      final env = {'GIT_INDEX_FILE': '${scratch.path}/index'};
      _git(
        gitDir,
        ['--work-tree=$workTree', 'add', '--all', '--force', '--', '.'],
        environment: env,
      );
      return _git(gitDir, ['--work-tree=$workTree', 'write-tree'],
          environment: env);
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }

  @override
  String commitTree(
    String gitDir, {
    required String tree,
    required List<String> parents,
    required String message,
    required Actor actor,
  }) {
    return _git(
      gitDir,
      [
        'commit-tree',
        tree,
        for (final parent in parents) ...['-p', parent],
        '-m',
        message,
      ],
      environment: _identity(actor),
    );
  }

  // --------------------------------------------------------------------- refs

  @override
  RefUpdate updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  }) {
    // The compare-and-swap, and the one verb whose refusal is an ordinary
    // outcome: a non-zero exit means another actor got there first, or a gate
    // said no — never that anything is broken.
    final result = _run([
      '--git-dir=$gitDir',
      'update-ref',
      ref,
      newCommit.sha,
      (expected ?? Commit.zero).sha,
    ]);
    if (result.exitCode == 0) return const RefUpdate(moved: true);
    // Carried whole and unread. Which of the two refusals this is, is a
    // question the ontology asks — the port only stops throwing away the
    // answer.
    return RefUpdate(moved: false, report: _text(result.stderr).trim());
  }

  @override
  void branch(String gitDir, {required String name, required Commit startPoint}) {
    _git(gitDir, ['branch', '--', name, startPoint.sha]);
  }

  @override
  List<String> branches(String gitDir) {
    final out = _git(
      gitDir,
      ['for-each-ref', '--format=%(refname:strip=2)', 'refs/heads/'],
    );
    return _lines(out)..sort();
  }

  @override
  Commit? revParse(String gitDir, String rev) {
    final result = _run([
      '--git-dir=$gitDir',
      'rev-parse',
      '--verify',
      '--quiet',
      '$rev^{commit}',
    ]);
    if (result.exitCode != 0) return null;
    final sha = _text(result.stdout).trim();
    return sha.isEmpty ? null : Commit(sha);
  }

  // ------------------------------------------------------------------ history

  /// The record format: fields NUL-separated, records closed by a lone record
  /// separator, so a message carrying newlines survives the parse intact.
  static const String _logFormat =
      '%H%x00%P%x00%an%x00%ae%x00%aI%x00%B%x00%x1e';

  @override
  List<RawCommit> log(
    String gitDir, {
    required String ref,
    int? limit,
    List<String> excluding = const [],
  }) {
    final result = _run([
      '--git-dir=$gitDir',
      'log',
      '--first-parent',
      if (limit != null) '--max-count=$limit',
      '--format=$_logFormat',
      ref,
      if (excluding.isNotEmpty) ...['--not', ...excluding],
    ]);
    if (result.exitCode != 0) return const [];
    return _parseLog(_text(result.stdout));
  }

  @override
  RawCommit showCommit(String gitDir, Commit commit) {
    final out = _git(gitDir, [
      'show',
      '--no-patch',
      '--format=$_logFormat',
      commit.sha,
    ]);
    final parsed = _parseLog(out);
    if (parsed.isEmpty) throw StateError('no such commit: ${commit.sha}');
    return parsed.first;
  }

  static List<RawCommit> _parseLog(String raw) {
    final out = <RawCommit>[];
    for (final record in raw.split('\x1e')) {
      final trimmed = record.replaceAll('\n', '').isEmpty ? '' : record;
      if (trimmed.trim().isEmpty) continue;
      final fields = record.split('\x00');
      if (fields.length < 6) continue;
      final sha = fields[0].trim();
      if (sha.isEmpty) continue;
      out.add(RawCommit(
        sha: sha,
        parents: fields[1].trim().isEmpty ? const [] : fields[1].trim().split(' '),
        author: Attribution(fields[2], fields[3]),
        instant: DateTime.parse(fields[4].trim()),
        message: fields[5].trimRight(),
      ));
    }
    return out;
  }

  @override
  Diff diffTree(String gitDir, {required Commit from, required Commit to}) {
    final out = _git(gitDir, [
      'diff-tree',
      '-r',
      '--no-commit-id',
      '--name-status',
      '-z',
      from.sha,
      to.sha,
    ]);
    final fields = out.split('\x00').where((f) => f.isNotEmpty).toList();
    final changes = <Change>[];
    for (var i = 0; i + 1 < fields.length; i += 2) {
      final kind = switch (fields[i][0]) {
        'A' => ChangeKind.added,
        'D' => ChangeKind.deleted,
        _ => ChangeKind.modified,
      };
      changes.add(Change(path: fields[i + 1], kind: kind));
    }
    changes.sort((a, b) => a.path.compareTo(b.path));
    return Diff(changes);
  }

  // ---------------------------------------------------------------- worktrees

  @override
  void worktreeAdd(
    String gitDir, {
    required String path,
    required Commit at,
    String? branch,
  }) {
    Directory(path).parent.createSync(recursive: true);
    // A registration whose directory is gone would refuse the add by name,
    // and *stand this directory up again* is one act to whoever needs the
    // files. Prune clears exactly those and leaves every standing tree alone,
    // which is why this is not `--force`: that flag would also override the
    // one-attached-tree-per-branch guard the act path now depends on.
    _git(gitDir, ['worktree', 'prune']);
    // Detached names the commit directly; attached names the branch and lets
    // Git resolve its own tip, which is what makes the checkout a real
    // attachment rather than a detached tree that merely happens to sit at
    // the same sha.
    final target = branch ?? at.sha;
    final args = branch == null
        ? ['worktree', 'add', '--detach', path, target]
        : ['worktree', 'add', path, target];
    _git(gitDir, args);
  }

  @override
  List<String> worktreesOn(String gitDir, String branch) {
    final result = _run(['--git-dir=$gitDir', 'worktree', 'list', '--porcelain']);
    if (result.exitCode != 0) return const [];
    final target = 'refs/heads/$branch';
    final paths = <String>[];
    String? current;
    for (final line in _text(result.stdout).split('\n')) {
      if (line.startsWith('worktree ')) {
        current = line.substring('worktree '.length).trim();
      } else if (line.startsWith('branch ')) {
        if (current != null && line.substring('branch '.length).trim() == target) {
          paths.add(current);
        }
      } else if (line.isEmpty) {
        current = null;
      }
    }
    return paths..sort();
  }

  @override
  void worktreeRemove(String gitDir, {required String path}) {
    // Possession before deletion. Everything below this line destroys disk, and
    // the only claim that authorizes it is the repository's own register.
    if (!_linkedWorktrees(gitDir).contains(_canonical(path))) {
      throw WorktreeNotOurs(path, repository: gitDir);
    }
    // `_git` and not `_run`: a refusal from the substrate is a fault of ours and
    // must travel. Read and discarded, it became an instruction to delete by
    // hand whatever Git had just declined to touch.
    _git(gitDir, ['worktree', 'remove', '--force', path]);
    // Deregistering is the half that matters: a directory deleted behind Git's
    // back leaves the entry standing, which is precisely the leak the API
    // exists to prevent. The residue below is reached only after Git removed a
    // tree we own, and is a no-op in every ordinary case.
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _run(['--git-dir=$gitDir', 'worktree', 'prune']);
  }

  @override
  WorktreeCheckout worktreeCheckout(String path, {required Commit to}) {
    // Asked from inside the worktree, not by `--git-dir`/`--work-tree`: a
    // linked worktree carries its own private index, and only Git's own
    // discovery from the tree itself finds it — the same reason
    // [worktreeHead] and [currentBranch] are asked this way.
    final result = _run(['checkout', to.sha], workingDirectory: path);
    if (result.exitCode == 0) return const WorktreeCheckout(moved: true);
    // Exit 1 is Git's own line between a decided refusal and a fault: a tree
    // still carrying local changes exits 1 with "would be overwritten"; an
    // unknown revision or a directory that is no repository at all exits
    // 128. Only the first is this member's business — the second is ours to
    // fix, not the caller's to interpret, and must travel as a fault.
    if (result.exitCode == 1) {
      return WorktreeCheckout(moved: false, report: _text(result.stderr).trim());
    }
    throw _failure(['checkout', to.sha], result);
  }

  @override
  WorktreeCommit commitInWorktree(
    String path, {
    required String message,
    required Actor actor,
  }) {
    // **Attachment is checked before anything is staged, because Git will
    // not refuse.** A commit in a detached worktree succeeds: the tree's own
    // HEAD advances, no ref holds the object, and the act is orphaned the
    // instant anyone looks away — a landing that landed nowhere, reported as
    // success. Measured, not assumed. So the only refusal there is, is ours.
    final following = currentBranch(path);
    if (following == null) {
      throw StateError('the worktree at $path follows no branch');
    }
    // Asked from inside the worktree, like every other member that acts on
    // one: a linked worktree carries its own index and its own HEAD, and only
    // Git's discovery from the tree itself finds them.
    final staged = _run(
      ['add', '--all', '--force', '--', '.'],
      workingDirectory: path,
    );
    if (staged.exitCode != 0) {
      throw _failure(const ['add', '--all'], staged);
    }
    final result = _run(
      // `--allow-empty`: an act that deposited nothing is still an act, and
      // the judgment about payloads is nobody's down here. `--no-verify`
      // stays off — a gate is the point.
      ['commit', '--allow-empty', '--message', message],
      workingDirectory: path,
      environment: _identity(actor),
    );
    if (result.exitCode == 0) {
      final landed = _run(['rev-parse', 'HEAD'], workingDirectory: path);
      if (landed.exitCode != 0) {
        throw _failure(const ['rev-parse', 'HEAD'], landed);
      }
      return WorktreeCommit(commit: Commit(_text(landed.stdout).trim()));
    }
    // A listener at `reference-transaction` refusing is an ordinary outcome
    // and travels as a value; Git writes its own line on stderr and the
    // gate's words beneath it. Everything else — no worktree here, a tree
    // Git declined to touch — is a fault of ours and must travel as one,
    // which is why the report is read for the substrate's own marker rather
    // than assumed.
    final report = _text(result.stderr).trim();
    final said = report.isEmpty ? _text(result.stdout).trim() : report;
    if (!said.contains('aborted by hook')) {
      throw _failure(const ['commit'], result);
    }
    return WorktreeCommit(report: said);
  }

  @override
  void worktreeDiscard(String path, {required Commit to}) {
    // Two halves, because tracked and untracked are two different disks to
    // Git: `reset --hard` restores what the commit names, and `clean -fd`
    // removes what it does not. Either alone leaves the tree dirty, and a
    // tree left dirty is the next act refused.
    final reset = _run(['reset', '--hard', to.sha], workingDirectory: path);
    if (reset.exitCode != 0) {
      throw _failure(['reset', '--hard', to.sha], reset);
    }
    final cleaned = _run(['clean', '--force', '-d'], workingDirectory: path);
    if (cleaned.exitCode != 0) {
      throw _failure(const ['clean', '--force', '-d'], cleaned);
    }
  }

  @override
  List<String> worktreeDirtyPaths(String path) {
    final result = _run(['status', '--porcelain'], workingDirectory: path);
    if (result.exitCode != 0) {
      throw _failure(['status', '--porcelain'], result);
    }
    final paths = <String>[];
    // Not `_lines`: its trim would eat the status column's own leading
    // space and shift every field left, corrupting the very columns this
    // parse depends on.
    for (final line in _text(result.stdout).split('\n')) {
      if (line.isEmpty) continue;
      // `XY<space>path`, or `XY<space>old -> new` for a rename: the field
      // starts at column 3, and only the arrow's right side is where the
      // path stands now.
      final field = line.length > 3 ? line.substring(3) : line;
      final arrow = field.indexOf(' -> ');
      paths.add(arrow < 0 ? field : field.substring(arrow + 4));
    }
    return paths..sort();
  }

  /// The **linked** worktrees this repository has registered, canonical and
  /// absolute — its register of what it may discard.
  ///
  /// The first record `worktree list` prints is the repository's main working
  /// tree (or the bare repository itself), and it is dropped: a repository's own
  /// tree is not a tenancy of ours, and it is exactly the directory a wrong path
  /// most often names.
  Set<String> _linkedWorktrees(String gitDir) {
    final result = _run(['--git-dir=$gitDir', 'worktree', 'list', '--porcelain']);
    if (result.exitCode != 0) return const {};
    final paths = [
      for (final line in _text(result.stdout).split('\n'))
        if (line.startsWith('worktree ')) line.substring('worktree '.length).trim(),
    ];
    return {for (final path in paths.skip(1)) _canonical(path)};
  }

  /// One spelling for one directory. The register answers in the substrate's
  /// resolved spelling and a caller types whatever it holds; on a machine whose
  /// temp is reached through a link the two differ, and a comparison between
  /// vocabularies would refuse a real tenancy — or, before the claim existed,
  /// admit somebody else's.
  static String _canonical(String path) {
    final dir = Directory(path);
    return dir.existsSync() ? dir.resolveSymbolicLinksSync() : path;
  }

  @override
  String? worktreeRepository(String path) {
    if (!Directory(path).existsSync()) return null;
    // `--git-common-dir` and not `--absolute-git-dir`: asked from inside a
    // worktree the latter answers with that worktree's *private* directory,
    // where no table and no history live, and the mistake fails silently.
    final result = _run(
      ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      workingDirectory: path,
    );
    if (result.exitCode != 0) return null;
    final answer = _text(result.stdout).trim();
    if (answer.isEmpty) return null;
    // The question Git answered is *which repository contains this directory*,
    // which every ordinary subdirectory answers. Possession is the second
    // question, and only the register answers it.
    return _linkedWorktrees(answer).contains(_canonical(path)) ? answer : null;
  }

  @override
  Commit? worktreeHead(String path) {
    if (!Directory(path).existsSync()) return null;
    // **Possession before reading.** `rev-parse HEAD` asked inside a directory
    // that is no worktree at all does not fail: Git walks *up* and answers for
    // whatever repository contains it. A stage standing under a place that
    // happens to live inside a checkout therefore reports that checkout's head
    // — a commit from another line entirely, and a plausible one, which is the
    // worst kind. The question here is *what does the tree standing here hold*,
    // and a directory nobody registered is not standing here at all.
    if (worktreeRepository(path) == null) return null;
    // Asked from inside the worktree, because that is the only vantage from
    // which `HEAD` means *this* tree: asked of the repository it would answer
    // with the bare repository's own head, which is another tree's business.
    final result = _run(['rev-parse', 'HEAD'], workingDirectory: path);
    if (result.exitCode != 0) return null;
    final answer = _text(result.stdout).trim();
    return answer.isEmpty ? null : Commit(answer);
  }

  // -------------------------------------------------------- the superproject

  @override
  String? topLevel(String path) {
    if (!Directory(path).existsSync()) return null;
    final result = _run(
      ['rev-parse', '--path-format=absolute', '--show-toplevel'],
      workingDirectory: path,
    );
    if (result.exitCode != 0) return null;
    final answer = _text(result.stdout).trim();
    return answer.isEmpty ? null : answer;
  }

  @override
  String? currentBranch(String workTree) {
    final result = _run(
      ['symbolic-ref', '--quiet', '--short', 'HEAD'],
      workingDirectory: workTree,
    );
    if (result.exitCode != 0) return null;
    final name = _text(result.stdout).trim();
    return name.isEmpty ? null : name;
  }

  @override
  List<String> branchesIn(String workTree) {
    final result = _run(
      ['for-each-ref', '--format=%(refname:strip=2)', 'refs/heads/'],
      workingDirectory: workTree,
    );
    if (result.exitCode != 0) return const [];
    return _lines(_text(result.stdout))..sort();
  }

  @override
  void stageGitlink(String workTree, {required String path, required Commit at}) {
    final result = _run(
      ['update-index', '--add', '--cacheinfo', '160000,${at.sha},$path'],
      workingDirectory: workTree,
    );
    if (result.exitCode != 0) {
      throw _failure(['update-index', '--cacheinfo', path], result);
    }
  }

  @override
  void unstageGitlink(String workTree, String path) {
    // `--force-remove` drops the entry whether or not the file stands on disk,
    // which is the only form that reaches a gitlink: the directory it names is
    // a repository the superproject never reads.
    _run(
      ['update-index', '--force-remove', '--', path],
      workingDirectory: workTree,
    );
  }

  @override
  List<({String mode, String sha, String path})> stagedEntries(
    String workTree,
    String path,
  ) {
    final result = _run(
      ['ls-files', '--stage', '-z', '--', path],
      workingDirectory: workTree,
    );
    if (result.exitCode != 0) return const [];
    final entries = <({String mode, String sha, String path})>[];
    for (final record in _text(result.stdout).split('\x00')) {
      if (record.trim().isEmpty) continue;
      // `<mode> <sha> <stage>\t<path>` — and the path may hold spaces, so the
      // tab is the only safe split and `-z` is what makes the record boundary
      // safe as well.
      final halves = record.split('\t');
      if (halves.length < 2) continue;
      final fields = halves.first.split(' ');
      if (fields.length < 2) continue;
      entries.add((
        mode: fields[0],
        sha: fields[1],
        path: halves.sublist(1).join('\t'),
      ));
    }
    return entries;
  }

  @override
  Commit? stagedGitlink(String workTree, String path) {
    final result = _run(
      ['ls-files', '--stage', '-z', '--', path],
      workingDirectory: workTree,
    );
    if (result.exitCode != 0) return null;
    for (final record in _text(result.stdout).split('\x00')) {
      if (record.trim().isEmpty) continue;
      // `<mode> <sha> <stage>\t<path>` — the mode is the whole question.
      final fields = record.split('\t').first.split(' ');
      if (fields.length < 2 || fields[0] != '160000') return null;
      return Commit(fields[1]);
    }
    return null;
  }

  // ------------------------------------------------------------------ remotes

  @override
  List<Remote> remotes(String gitDir) {
    final result = _run([
      '--git-dir=$gitDir',
      'config',
      '--get-regexp',
      r'^remote\..*\.url$',
    ]);
    // Exit 1 is "no matches" — an empty answer, not a fault.
    if (result.exitCode != 0) return const [];
    return [
      for (final line in _lines(_text(result.stdout)))
        if (line.indexOf(' ') > 0)
          Remote(
            name: line
                .substring(0, line.indexOf(' '))
                .replaceFirst('remote.', '')
                .replaceFirst(RegExp(r'\.url$'), ''),
            url: line.substring(line.indexOf(' ') + 1).trim(),
          ),
    ];
  }

  @override
  void addRemote(String gitDir, {required String name, required String url}) {
    _git(gitDir, ['remote', 'add', name, url]);
  }

  @override
  void setRemoteUrl(String gitDir, {required String name, required String url}) {
    _git(gitDir, ['remote', 'set-url', name, url]);
  }

  // --------------------------------------------------------------- the network

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) async {
    Directory(gitDir).parent.createSync(recursive: true);
    await _gitAsync([
      'clone',
      if (bare) '--bare',
      '--quiet',
      source,
      gitDir,
    ]);
    // **A bare clone has no fetch refspec, and without one standing is
    // unanswerable.** `git clone --bare` deliberately omits
    // `remote.origin.fetch`, so a later `git fetch origin` writes nothing but
    // `FETCH_HEAD`: no `refs/remotes/origin/*` ever appears, no branch can
    // carry an upstream, and every "is this published?" costs a round trip to
    // the remote that a human has to remember to make. Restoring the standard
    // refspec is purely additive — it creates remote-tracking refs and never
    // touches `refs/heads/*`, which in an entity *are the instances*, several
    // of which legitimately exist only here.
    //
    // Written here rather than beside [setRemoteUrl] because it holds of every
    // clone we make regardless of who calls it, and it is url-independent: the
    // staged install path clones from a temp directory and corrects the url
    // afterwards, and this refspec is already correct for both.
    _git(gitDir, [
      'config',
      'remote.origin.fetch',
      '+refs/heads/*:refs/remotes/origin/*',
    ]);
  }

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) async {
    await _gitAsync([
      '--git-dir=$gitDir',
      'push',
      '--quiet',
      remote,
      if (ref != null) ref else '--all',
    ]);
  }

  @override
  Future<Commit?> fetch(
    String gitDir, {
    required String remote,
    required String ref,
  }) async {
    // Deliberately fetched into no local ref: `FETCH_HEAD` is where the line
    // lands, and moving anything is the ontology's act one floor up.
    final result = await Process.run(
      executable,
      ['--git-dir=$gitDir', 'fetch', '--quiet', remote, ref],
      environment: {
        for (final e in Platform.environment.entries)
          if (!_poisoned.contains(e.key)) e.key: e.value,
      },
      includeParentEnvironment: false,
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (result.exitCode != 0) {
      // A remote that does not carry this ref is an ordinary answer — the
      // instance simply does not exist over there. Every other failure is a
      // network or repository fault and stays a throw.
      final complaint = _text(result.stderr);
      if (complaint.contains("couldn't find remote ref")) return null;
      throw _failure(['fetch', remote, ref], result);
    }
    return revParse(gitDir, 'FETCH_HEAD');
  }

  static List<String> _lines(String raw) => [
        for (final line in raw.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
}
