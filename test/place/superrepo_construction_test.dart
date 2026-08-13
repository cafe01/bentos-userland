import 'dart:io';

import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// The pin against the real substrate.
///
/// The contract suite proves the primitive's behaviour over a double; it cannot
/// prove the one thing that matters most here — that what we wrote **is a
/// gitlink**. So this asks Git itself, through porcelain nobody of ours wrote:
/// if an ordinary `ls-tree` does not report mode `160000`, we did not write a
/// gitlink, we wrote something else with that name.
void main() {
  group('the pin is a real gitlink', () {
    const git = ProcessGit();
    late Directory scratch;
    late String campus;
    late String pinned;

    /// Git, run raw — the reader standing in for any third party that reads a
    /// superproject. Deliberately not the port: a proof that used our own code
    /// to read back our own write would prove only that we are consistent.
    ProcessResult raw(List<String> args, {String? at}) => Process.runSync(
          'git',
          [
            '-c', 'user.name=test',
            '-c', 'user.email=test@local',
            ...args,
          ],
          workingDirectory: at ?? campus,
        );

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('place_superrepo_');
      campus = '${scratch.path}/campus';
      // The superproject: an ordinary working repository, as a place that a
      // person inhabits always is.
      Directory(campus).createSync(recursive: true);
      raw(['init', '--quiet', '.']);
      Directory('$campus/workshop/.place').createSync(recursive: true);

      // Something to pin: a repository of its own, with one commit.
      final other = '${scratch.path}/brain.git';
      git.init(other);
      final work = Directory('${scratch.path}/w')..createSync(recursive: true);
      File('${work.path}/page.md').writeAsStringSync('a page');
      final tree = git.writeTree(other, workTree: work.path);
      pinned = git.commitTree(other,
          tree: tree, parents: const [], message: 'genesis', actor: testActor);
    });

    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test('ls-tree reports mode 160000 at the installation\'s path', () {
      Place('$campus/workshop')
          .register('bentos.brain', url: 'git@host:brain.git', path: 'brain', sha: pinned);

      // The pin stops at the index: the inhabitant commits, never the
      // primitive. This line is the inhabitant.
      raw(['add', '--', '.gitmodules']);
      final commit = raw(['commit', '--quiet', '-m', 'install bentos.brain']);
      expect(commit.exitCode, 0, reason: '${commit.stderr}');

      final lsTree = raw(['ls-tree', 'HEAD', 'workshop/brain']);
      expect(lsTree.exitCode, 0, reason: '${lsTree.stderr}');
      expect(
        '${lsTree.stdout}'.trim(),
        '160000 commit $pinned\tworkshop/brain',
        reason: 'if the mode is not 160000 we did not write a gitlink',
      );
    });

    test('and the place reads its own pin back from the index', () {
      final place = Place('$campus/workshop');
      place.register('bentos.brain', url: 'u', path: 'brain', sha: pinned);
      expect(place.installed.single.sha, pinned);
    });

    test('a pin written and not committed is visible and not yet true', () {
      final place = Place('$campus/workshop');
      place.register('bentos.brain', url: 'u', path: 'brain', sha: pinned);

      expect(place.installed.single.sha, pinned, reason: 'visible');
      final lsTree = raw(['ls-tree', 'HEAD', 'workshop/brain']);
      expect(lsTree.exitCode, isNot(0),
          reason: 'not yet true — there is no HEAD to read it out of, because '
              'committing is the inhabitant\'s act and nobody has performed it');
    });
  });
}
