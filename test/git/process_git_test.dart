import 'dart:io';

import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The real port, on the questions where **the fake is the better machine**.
///
/// A double that models a claim the substrate does not make turns every gate
/// above it into a proof about the model. Possession is exactly such a claim:
/// the fake answers only for worktrees it registered, so everything written
/// against it was written for a port that tells the truth about ownership —
/// while the real one asked Git a question Git answers for the *neighbourhood*.
/// These gates stand at the tier where that difference exists at all.
void main() {
  const git = ProcessGit();
  late Directory scratch;

  setUp(() {
    scratch = Directory(
      Directory.systemTemp.createTempSync('process_git_').resolveSymbolicLinksSync(),
    );
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  /// An ordinary repository with one commit, and its head.
  String enclosing(String name) {
    final path = p.join(scratch.path, name);
    Directory(path).createSync(recursive: true);
    Process.runSync('git', ['init', '--quiet', path]);
    Process.runSync('git', [
      '-C', path,
      '-c', 'user.email=gate@bentos',
      '-c', 'user.name=gate',
      'commit', '--quiet', '--allow-empty', '-m', 'one',
    ]);
    return path;
  }

  group('worktreeHead', () {
    test('a plain directory inside a repository holds no tree of anyone’s',
        () async {
      final repo = enclosing('outer');
      final inside = Directory(p.join(repo, 'sub', 'dir'))
        ..createSync(recursive: true);

      // `rev-parse HEAD` run here *succeeds* — Git walks up and answers for the
      // repository that contains the directory. That answer is a real commit
      // from a real line, which is what makes it dangerous: a caller asking
      // *what does the tree standing here hold* gets a plausible number about
      // somebody else's history and no way to tell.
      final walked = Process.runSync(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: inside.path,
      );
      expect(walked.exitCode, 0, reason: 'the substrate does answer — that is the trap');

      expect(git.worktreeHead(inside.path), isNull);
      expect(git.worktreeRepository(inside.path), isNull);
    });

    test('a worktree this repository registered answers with its own commit',
        () async {
      final repo = enclosing('owner');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');

      git.worktreeAdd(gitDir, path: where, at: head);

      expect(git.worktreeHead(where), head);
      expect(git.worktreeRepository(where), isNotNull);
    });

    test('a directory that never was is null, not a fault', () {
      expect(git.worktreeHead(p.join(scratch.path, 'nowhere')), isNull);
    });
  });
}
