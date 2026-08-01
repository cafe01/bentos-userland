import 'package:bentos_userland/git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:test/test.dart';

import '../git/fake_git.dart';

/// The Git half of `Place` — the landlord's half of installing.
///
/// > **The tenant asks; the landlord records.**
///
/// What is asserted here is the record and the pin: that a place enumerates
/// what is installed in it, that the pin is a **gitlink** and not a value
/// invented in a config file, and that a place lying in no repository says so
/// rather than pretending. That the gitlink is a real one — mode `160000`, read
/// back by an ordinary `git ls-tree` — is asserted against real Git in
/// `construction_test.dart`; a fake cannot prove that and does not try.
void main() {
  /// A place at [root], inside a repository whose working tree is [workTree].
  ({Place place, FakeGit git}) placeIn(
    dynamic fs, {
    String root = '/campus/workshop',
    String? workTree = '/campus',
  }) {
    fs.directory('$root/.place').createSync(recursive: true);
    final git = FakeGit();
    if (workTree != null) git.workTrees.add(workTree);
    return (place: Place(root), git: git);
  }

  group('registration', () {
    test('records path and url, and enumerates what is installed', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain',
              url: 'git@host:brain.git', path: 'brain', sha: 'a' * 40);

          expect(place.installed.single.name, 'bentos.brain');
          expect(place.installed.single.url, 'git@host:brain.git');
          expect(place.installed.single.path, 'brain');
        });
      });
    });

    test('the pin is nowhere in .gitmodules — that file carries the address', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain',
              url: 'git@host:brain.git', path: 'brain', sha: 'a' * 40);
        });
        final modules = fs.file('/campus/workshop/.gitmodules').readAsStringSync();
        expect(modules, contains('path = brain'));
        expect(modules, contains('url = git@host:brain.git'));
        expect(modules, isNot(contains('sha')),
            reason: 'the pin is a gitlink; a sha key here would be a second '
                'answer to a question the substrate already answers');
      });
    });

    test('lookup answers the single step of the entity\'s upward walk', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'b' * 40);
          expect(place.lookup('bentos.brain')?.sha, 'b' * 40);
          expect(place.lookup('nobody.here'), isNull);
        });
      });
    });

    test('unregister forgets the record', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'c' * 40);
          place.unregister('bentos.brain');
          expect(place.installed, isEmpty);
        });
      });
    });
  });

  group('the pin', () {
    test('is a gitlink in the enclosing repository, at the path it knows', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'd' * 40);
        });
        expect(git.index['/campus'], isNotNull,
            reason: 'the index written is the enclosing repository\'s, not the place\'s');
        expect(git.index['/campus']!['workshop/brain'],
            (mode: '160000', sha: 'd' * 40),
            reason: 'mode 160000 at the path the superproject knows the '
                'installation by — the place\'s own path is not that path');
      });
    });

    test('moves, and installed reports the new value', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'e' * 40);
          place.pin('bentos.brain', 'f' * 40);
          expect(place.installed.single.sha, 'f' * 40);
        });
      });
    });

    test('is read from the substrate, never from what the caller passed', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: '1' * 40);
          // Another hand moves the index — a rebase, a checkout, a person.
          git.stageGitlink('/campus',
              path: 'workshop/brain', at: Commit('2' * 40));
          expect(place.installed.single.sha, '2' * 40,
              reason: 'a live handle re-reads; the pin is the substrate\'s fact');
        });
      });
    });

    test('pinning an unknown name does nothing', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.pin('nobody.here', 'a' * 40);
          expect(git.index['/campus'] ?? const {}, isEmpty);
        });
      });
    });

    test('a place inside no repository holds no pin, and says so', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs, workTree: null);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'a' * 40);
          expect(place.installed.single.name, 'bentos.brain',
              reason: 'the record is still enumerable');
          expect(place.installed.single.sha, isEmpty,
              reason: 'only the commit it is held at is absent');
        });
      });
    });

    test('what is staged at the path but is not a gitlink is not a pin', () {
      runInMemoryFs((fs) {
        final (:place, :git) = placeIn(fs);
        runWithGit(git, () {
          place.register('bentos.brain', url: 'u', path: 'brain', sha: 'a' * 40);
          git.index['/campus']!['workshop/brain'] =
              (mode: '100644', sha: 'a' * 40);
          expect(place.installed.single.sha, isEmpty,
              reason: 'an ordinary file there is not a weaker pin — it is a '
                  'different thing entirely');
        });
      });
    });
  });
}
