import 'package:bentos_userland/entity.dart';

import '../git/fake_git.dart';
import 'helpers.dart';

/// What one run of the coreutil left behind: the two streams and the number the
/// process would have exited with.
typedef Run = ({String out, String err, int code});

/// The coreutil driven **in process** — no spawn, no PATH, no binary.
///
/// [EntityRunner] takes its streams and its working directory as arguments
/// precisely so that this is possible: the surface under test is the runner,
/// and a subprocess would only add a shell between the assertion and the thing
/// it is asserting about. What Tier C proves about the real substrate is proven
/// elsewhere; the port here is the fake, installed as the ambient for the whole
/// call, exactly as it is for a library test.
final class Cli {
  Cli(this.site, {FakeGit? git}) : git = git ?? site.git;

  final Site site;
  final FakeGit git;

  Future<Run> run(List<String> args, {String? cwd}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = EntityRunner(
      out: out,
      err: err,
      currentDirectory: cwd ?? site.root.path,
    );
    await runWithGitAsync(git, () => runner.run(args));
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }
}
