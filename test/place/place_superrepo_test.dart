import 'dart:io';

import 'package:bentos_userland/git.dart';
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:test/test.dart';

/// The Git half of `Place` — the landlord's half of installing.
///
/// > **The tenant asks; the landlord records.**
///
/// What is asserted here is the record and the pin: that a place enumerates
/// what is installed in it, that the pin is a **gitlink** and not a value
/// invented in a config file, and that a place lying in no repository says so
/// rather than pretending. Against real Git throughout: `superrepo_
/// construction_test.dart` already proves the gitlink is real (mode `160000`,
/// read back by an ordinary `git ls-tree`) on the same substrate, and a fake
/// filesystem cannot stand under real Git at all — a worktree is real files
/// by definition.
void main() {
  const git = ProcessGit();
  late Directory scratch;
  late String campus;

  /// A place at `$campus/workshop` — inside a real repository at [campus] by
  /// default, or standing in no repository at all when [enclosed] is false.
  Place placeIn({bool enclosed = true}) {
    final root = '$campus/workshop';
    Directory('$root/.place').createSync(recursive: true);
    if (enclosed) {
      final result = Process.runSync('git', ['init', '--quiet', campus]);
      if (result.exitCode != 0) {
        throw ProcessException('git', ['init', campus], '${result.stderr}');
      }
    }
    return Place(root);
  }

  ProcessResult raw(List<String> args) =>
      Process.runSync('git', args, workingDirectory: campus);

  /// The staged entry at [path] in the campus's own index, or null when
  /// nothing is staged there — read the same way any third party reading the
  /// superproject would, never through the port that just wrote it.
  ({String mode, String sha})? stagedAt(String path) {
    final result = raw(['ls-files', '--stage', '--', path]);
    final line = '${result.stdout}'.trim();
    if (line.isEmpty) return null;
    final fields = line.split(RegExp(r'\s+'));
    return (mode: fields[0], sha: fields[1]);
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('place_superrepo_');
    campus = '${scratch.path}/campus';
    Directory(campus).createSync(recursive: true);
  });

  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  group('registration', () {
    test('records path and url, and enumerates what is installed', () {
      final place = placeIn();
      place.register('bentos.brain',
          url: 'git@host:brain.git', path: 'brain', sha: 'a' * 40);

      expect(place.installed.single.name, 'bentos.brain');
      expect(place.installed.single.url, 'git@host:brain.git');
      expect(place.installed.single.path, 'brain');
    });

    test('the pin is nowhere in .gitmodules — that file carries the address', () {
      final place = placeIn();
      place.register('bentos.brain',
          url: 'git@host:brain.git', path: 'brain', sha: 'a' * 40);

      final modules = File('$campus/workshop/.gitmodules').readAsStringSync();
      expect(modules, contains('path = brain'));
      expect(modules, contains('url = git@host:brain.git'));
      expect(modules, isNot(contains('sha')),
          reason: 'the pin is a gitlink; a sha key here would be a second '
              'answer to a question the substrate already answers');
    });

    test('lookup answers the single step of the entity\'s upward walk', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'b' * 40);
      expect(place.lookup('bentos.brain')?.sha, 'b' * 40);
      expect(place.lookup('nobody.here'), isNull);
    });

    test('unregister forgets the record', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'c' * 40);
      place.unregister('bentos.brain');
      expect(place.installed, isEmpty);
    });
  });

  group('the pin', () {
    test('is a gitlink in the enclosing repository, at the path it knows', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'd' * 40);

      final staged = stagedAt('workshop/brain');
      expect(staged, isNotNull,
          reason: 'the index written is the enclosing repository\'s, not the '
              'place\'s');
      expect(staged, (mode: '160000', sha: 'd' * 40),
          reason: 'mode 160000 at the path the superproject knows the '
              'installation by — the place\'s own path is not that path');
    });

    test('moves, and installed reports the new value', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'e' * 40);
      place.pin('bentos.brain', 'f' * 40);
      expect(place.installed.single.sha, 'f' * 40);
    });

    test('is read from the substrate, never from what the caller passed', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: '1' * 40);
      // Another hand moves the index — a rebase, a checkout, a person.
      git.stageGitlink(campus, path: 'workshop/brain', at: Commit('2' * 40));
      expect(place.installed.single.sha, '2' * 40,
          reason: 'a live handle re-reads; the pin is the substrate\'s fact');
    });

    test('pinning an unknown name does nothing', () {
      final place = placeIn();
      place.pin('nobody.here', 'a' * 40);
      expect('${raw(['ls-files', '--stage']).stdout}'.trim(), isEmpty);
    });

    test('a place inside no repository holds no pin, and says so', () {
      final place = placeIn(enclosed: false);
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'a' * 40);
      expect(place.installed.single.name, 'bentos.brain',
          reason: 'the record is still enumerable');
      expect(place.installed.single.sha, isEmpty,
          reason: 'only the commit it is held at is absent');
    });

    test('what is staged at the path but is not a gitlink is not a pin', () {
      final place = placeIn();
      place.register('bentos.brain', url: 'u', path: 'brain', sha: 'a' * 40);

      // Overwrite the gitlink with an ordinary tracked file at the same path.
      final blob = File('${scratch.path}/blob.txt')
        ..writeAsStringSync('not a gitlink');
      final hashed = raw(['hash-object', '-w', blob.path]);
      expect(hashed.exitCode, 0, reason: '${hashed.stderr}');
      final blobSha = '${hashed.stdout}'.trim();
      final staged = raw([
        'update-index',
        '--add',
        '--cacheinfo',
        '100644,$blobSha,workshop/brain',
      ]);
      expect(staged.exitCode, 0, reason: '${staged.stderr}');

      expect(place.installed.single.sha, isEmpty,
          reason: 'an ordinary file there is not a weaker pin — it is a '
              'different thing entirely');
    });
  });
}
