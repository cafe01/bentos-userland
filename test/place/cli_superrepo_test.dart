import 'dart:io';

import 'package:bentos_userland/src/git/process_git.dart';
import 'package:bentos_userland/src/place/place.dart';
import 'package:bentos_userland/src/place/place_runner.dart';
import 'package:test/test.dart';

import '../entity/helpers.dart';

/// The superrepo verbs through the coreutil — `ls`, `pin`, `timeline`.
///
/// Driven against **a real repository**, deliberately: these three verbs exist
/// to report what Git holds, and a fake filesystem has no branches and no
/// index for them to report. The sister taught this expensively — a surface
/// proven only through the library is a surface nobody has typed.
void main() {
  late Directory scratch;
  late String campus;
  late String pinned;

  Future<({String out, String err, int code})> runPlace(
    List<String> args, {
    required String cwd,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = PlaceRunner(out: out, err: err, currentDirectory: cwd);
    await runner.run(args);
    return (out: out.toString(), err: err.toString(), code: runner.exitCode);
  }

  ProcessResult raw(List<String> args) => Process.runSync(
        'git',
        ['-c', 'user.name=t', '-c', 'user.email=t@l', ...args],
        workingDirectory: campus,
      );

  setUp(() {
    const git = ProcessGit();
    scratch = Directory.systemTemp.createTempSync('place_cli_super_');
    campus = '${scratch.path}/campus';
    Directory(campus).createSync(recursive: true);
    raw(['init', '--quiet', '--initial-branch=main', '.']);
    Directory('$campus/workshop/.place').createSync(recursive: true);
    File('$campus/README.md').writeAsStringSync('campus');
    raw(['add', '-A']);
    raw(['commit', '--quiet', '-m', 'the campus']);

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

  void install() => Place('$campus/workshop')
      .register('bentos.brain', url: 'file://$campus/brain.git', path: 'brain', sha: pinned);

  group('place ls', () {
    test('prints name, origin and pin, one tab-separated line each', () async {
      install();
      final r = await runPlace(['ls'], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out.trim(), 'bentos.brain\tfile://$campus/brain.git\t$pinned');
    });

    test('an empty place prints nothing and is not an error', () async {
      final r = await runPlace(['ls'], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out, isEmpty, reason: 'a reach that selects nothing is an answer');
    });
  });

  group('place pin', () {
    test('with no sha, reads the commit held true', () async {
      install();
      final r = await runPlace(['pin', 'bentos.brain'], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out.trim(), pinned);
    });

    test('with a sha, moves it and prints what the substrate now holds', () async {
      install();
      final moved = 'b' * 40;
      final r = await runPlace(['pin', 'bentos.brain', moved], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out.trim(), moved);

      final staged = raw(['ls-files', '-s', '--', 'workshop/brain']);
      expect('${staged.stdout}', startsWith('160000 $moved'),
          reason: 'still a gitlink after the move, read by git itself');
    });

    test('prints what is held, not what was asked — they differ outside a repository', () async {
      final loose = '${scratch.path}/loose';
      Directory('$loose/.place').createSync(recursive: true);
      Place(loose).register('bentos.brain', url: 'u', path: 'brain', sha: pinned);

      final r = await runPlace(['pin', 'bentos.brain', 'c' * 40], cwd: loose);
      expect(r.code, 0);
      expect(r.out.trim(), isEmpty,
          reason: 'there is no index to land the gitlink in, so nothing is '
              'held — echoing the argument would report a pin that does not exist');
    });

    test('an unknown name exits 1 — the presence test a script branches on', () async {
      final r = await runPlace(['pin', 'nobody.here'], cwd: '$campus/workshop');
      expect(r.code, 1);
      expect(r.err, contains('no installation named'));
    });
  });

  group('place timeline', () {
    test('prints the branch in view', () async {
      final r = await runPlace(['timeline'], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out.trim(), 'main');
    });

    test('ls prints every timeline, the current one marked', () async {
      raw(['branch', 'experiment']);
      final r = await runPlace(['timeline', 'ls'], cwd: '$campus/workshop');
      expect(r.code, 0);
      expect(r.out, contains('*\tmain'));
      expect(r.out, contains(' \texperiment'));
    });

    test('a place outside any repository stands outside time, and says so', () async {
      final loose = '${scratch.path}/loose';
      Directory('$loose/.place').createSync(recursive: true);
      final r = await runPlace(['timeline'], cwd: loose);
      expect(r.code, 0, reason: 'standing outside time is not an error');
      expect(r.err, contains('no timeline in view'));
      expect(r.out, isEmpty);
    });
  });
}
