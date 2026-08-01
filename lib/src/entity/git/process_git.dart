import '../model/actor.dart';
import '../model/commit.dart';
import '../model/remote.dart';
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

  @override
  void init(String gitDir, {bool bare = true}) =>
      throw UnimplementedError('ProcessGit.init');

  @override
  String hashObject(String gitDir, List<int> bytes) =>
      throw UnimplementedError('ProcessGit.hashObject');

  @override
  List<int> catFile(String gitDir, String object) =>
      throw UnimplementedError('ProcessGit.catFile');

  @override
  String writeTree(String gitDir, {required String workTree}) =>
      throw UnimplementedError('ProcessGit.writeTree');

  @override
  String commitTree(
    String gitDir, {
    required String tree,
    required List<String> parents,
    required String message,
    Actor? actor,
  }) =>
      throw UnimplementedError('ProcessGit.commitTree');

  @override
  bool updateRef(
    String gitDir, {
    required String ref,
    required Commit newCommit,
    required Commit? expected,
  }) =>
      throw UnimplementedError('ProcessGit.updateRef');

  @override
  void branch(String gitDir, {required String name, required Commit startPoint}) =>
      throw UnimplementedError('ProcessGit.branch');

  @override
  List<String> branches(String gitDir) =>
      throw UnimplementedError('ProcessGit.branches');

  @override
  Commit? revParse(String gitDir, String rev) =>
      throw UnimplementedError('ProcessGit.revParse');

  @override
  List<RawCommit> log(String gitDir, {required String ref, int? limit}) =>
      throw UnimplementedError('ProcessGit.log');

  @override
  RawCommit showCommit(String gitDir, Commit commit) =>
      throw UnimplementedError('ProcessGit.showCommit');

  @override
  Diff diffTree(String gitDir, {required Commit from, required Commit to}) =>
      throw UnimplementedError('ProcessGit.diffTree');

  @override
  void worktreeAdd(String gitDir, {required String path, required Commit at}) =>
      throw UnimplementedError('ProcessGit.worktreeAdd');

  @override
  void worktreeRemove(String gitDir, {required String path}) =>
      throw UnimplementedError('ProcessGit.worktreeRemove');

  @override
  List<Remote> remotes(String gitDir) =>
      throw UnimplementedError('ProcessGit.remotes');

  @override
  void addRemote(String gitDir, {required String name, required String url}) =>
      throw UnimplementedError('ProcessGit.addRemote');

  @override
  Future<void> clone(String source, String gitDir, {bool bare = true}) =>
      throw UnimplementedError('ProcessGit.clone');

  @override
  Future<void> push(String gitDir, {required String remote, String? ref}) =>
      throw UnimplementedError('ProcessGit.push');

  @override
  Future<void> fetch(String gitDir, {required String remote}) =>
      throw UnimplementedError('ProcessGit.fetch');
}
