import 'dart:io';

import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// The pin under two spellings of one directory.
///
/// Every other proof of the pin varies the *state* — which entity, which sha,
/// which cardinality — inside a single locality, and a defect that lives in the
/// spelling of a path survives all of them at once. This varies the locality
/// and holds the state fixed: the same registration, performed at a place
/// reached directly and at the same place reached through a symbolic link.
///
/// The pin is a path relative to the working tree it is indexed in, and Git
/// names that tree canonically. A place that answered with its anchor's
/// spelling would compute a relation between two vocabularies — under a linked
/// path, a chain of `../` climbing out of the repository — and Git would refuse
/// the gitlink. The two cases must therefore agree, and disagreeing is exactly
/// what the defect looked like.
void main() {
  group('the pin is written where the tree knows it', () {
    const git = ProcessGit();
    late Directory scratch;
    late String campus;
    late String pinned;

    /// Git, run raw — the third party reading back what we wrote, never our own
    /// port answering for itself.
    ProcessResult raw(List<String> args, {String? at}) => Process.runSync(
          'git',
          ['-c', 'user.name=test', '-c', 'user.email=test@local', ...args],
          workingDirectory: at ?? campus,
        );

    setUp(() {
      // Resolved: this habitat is the canonical one on every machine, so the
      // linked case below is the only one varying, whatever the system temp is.
      scratch = Directory(Directory.systemTemp
          .createTempSync('place_locality_')
          .resolveSymbolicLinksSync());
      campus = '${scratch.path}/real/campus';
      Directory(campus).createSync(recursive: true);
      raw(['init', '--quiet', '.']);
      Directory('$campus/workshop/.place').createSync(recursive: true);
      Link('${scratch.path}/link').createSync('${scratch.path}/real');

      final other = '${scratch.path}/brain.git';
      git.init(other);
      final work = Directory('${scratch.path}/w')..createSync(recursive: true);
      File('${work.path}/page.md').writeAsStringSync('a page');
      pinned = git.commitTree(other,
          tree: git.writeTree(other, workTree: work.path),
          parents: const [],
          message: 'genesis', actor: testActor);
    });

    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    /// One registration, performed through [anchor], read back two ways: by the
    /// place itself, and by Git, which must hold the gitlink at the path the
    /// tree knows the installation by — `workshop/brain`, and nothing else.
    void pinRoundTrips(String anchor) {
      final place = Place('$anchor/workshop');
      place.register('bentos.brain', url: 'u', path: 'brain', sha: pinned);

      expect(place.installed.single.sha, pinned,
          reason: 'the place must read back the pin it just wrote');

      final staged = raw(['ls-files', '--stage', '--', 'workshop/brain']);
      expect(staged.exitCode, 0, reason: '${staged.stderr}');
      expect(
        '${staged.stdout}'.trim(),
        '160000 $pinned 0\tworkshop/brain',
        reason: 'the index path is the tree\'s own, never the anchor\'s',
      );
    }

    test('reached directly', () {
      pinRoundTrips(campus);
    });

    test('reached through a symbolic link', () {
      pinRoundTrips('${scratch.path}/link/campus');
    });

    test('and both spellings are one place', () {
      expect(
        Place('${scratch.path}/link/campus/workshop').root.path,
        Place('$campus/workshop').root.path,
        reason: 'identity is the resolved root, so a link is not a second place',
      );
    });
  });
}
