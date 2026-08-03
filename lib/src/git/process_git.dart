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

  /// The identity the substrate demands. An [Actor] carries a name and at most
  /// an address; where Git insists on both, the address is derived and means
  /// nothing to anyone who reads it back.
  static Map<String, String> _identity(Actor? actor) {
    final who = actor ?? const Actor('unknown');
    final mail = who.email ?? '${who.name}@entity.local';
    return {
      'GIT_AUTHOR_NAME': who.name,
      'GIT_AUTHOR_EMAIL': mail,
      'GIT_COMMITTER_NAME': who.name,
      'GIT_COMMITTER_EMAIL': mail,
    };
  }

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
    Actor? actor,
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
  bool updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  }) {
    // The compare-and-swap, and the one verb whose refusal is an ordinary
    // outcome: a non-zero exit means another actor got there first, not that
    // anything is broken.
    final result = _run([
      '--git-dir=$gitDir',
      'update-ref',
      ref,
      newCommit.sha,
      (expected ?? Commit.zero).sha,
    ]);
    return result.exitCode == 0;
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
  List<RawCommit> log(String gitDir, {required String ref, int? limit}) {
    final result = _run([
      '--git-dir=$gitDir',
      'log',
      '--first-parent',
      if (limit != null) '--max-count=$limit',
      '--format=$_logFormat',
      ref,
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
        author: Actor(fields[2], email: fields[3].isEmpty ? null : fields[3]),
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
  void worktreeAdd(String gitDir, {required String path, required Commit at}) {
    Directory(path).parent.createSync(recursive: true);
    _git(gitDir, ['worktree', 'add', '--detach', '--force', path, at.sha]);
  }

  @override
  void worktreeRemove(String gitDir, {required String path}) {
    // Deregistering is the half that matters: a directory deleted behind Git's
    // back leaves the entry standing, which is precisely the leak the API
    // exists to prevent.
    _run(['--git-dir=$gitDir', 'worktree', 'remove', '--force', path]);
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _run(['--git-dir=$gitDir', 'worktree', 'prune']);
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
    return answer.isEmpty ? null : answer;
  }

  @override
  Commit? worktreeHead(String path) {
    if (!Directory(path).existsSync()) return null;
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
