import 'dart:io';

import 'package:bentos_userland/src/git/model/actor.dart';
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

  group('the identity cascade', () {
    /// Who Git recorded as the author of one commit object.
    String authorOf(String repo, String sha) => Process.runSync(
          'git',
          ['-C', repo, 'log', '-1', '--format=%an <%ae>', sha],
        ).stdout.toString().trim();

    /// A repository whose **config** names an identity — which is the thing the
    /// cascade is supposed to find. `enclosing` passes `-c` per command, and a
    /// flag on a command the port never runs answers for nothing.
    (String, String) groundOf(String name) {
      final repo = enclosing(name);
      final gitDir = p.join(repo, '.git');
      Process.runSync('git', ['-C', repo, 'config', 'user.name', 'gate']);
      Process.runSync('git', ['-C', repo, 'config', 'user.email', 'gate@bentos']);
      final tree = Process.runSync('git', ['-C', gitDir, 'rev-parse', 'HEAD^{tree}']);
      return (repo, tree.stdout.toString().trim());
    }

    test('no actor means no identity environment, so the machine answers', () {
      final (repo, tree) = groundOf('cascade');

      final made = git.commitTree(p.join(repo, '.git'),
          tree: tree, parents: [], message: 'two');

      // The defect this replaced: a null actor was substituted by
      // `Actor('unknown')` and exported, overriding Git's own cascade — so an
      // act whose content named its author was contradicted by its own commit,
      // permanently and on every remote that fetched the line.
      expect(authorOf(repo, made), isNot(contains('unknown')));
      expect(authorOf(repo, made), 'gate <gate@bentos>');
    });

    test('an actor is still the author, byte for byte', () {
      final (repo, tree) = groundOf('named');

      final made = git.commitTree(p.join(repo, '.git'),
          tree: tree,
          parents: [],
          message: 'two',
          actor: const Actor('alfred', email: 'alfred@bentos.life'));

      expect(authorOf(repo, made), 'alfred <alfred@bentos.life>');
    });
  });

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

  group('worktreeCheckout', () {
    test('an unforced move brings the tree to the new commit', () {
      final repo = enclosing('clean');
      final gitDir = p.join(repo, '.git');
      final first = git.revParse(gitDir, 'HEAD')!;
      File(p.join(repo, 'f.txt')).writeAsStringSync('one');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'two',
      ]);
      final second = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: first);

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isTrue);
      expect(result.report, isEmpty);
      expect(git.worktreeHead(where), second);
      expect(File(p.join(where, 'f.txt')).readAsStringSync(), 'one');
    });

    test('a dirty tree declines, and the person’s bytes survive the refusal',
        () {
      final repo = enclosing('dirty');
      final gitDir = p.join(repo, '.git');
      File(p.join(repo, 'f.txt')).writeAsStringSync('base');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'one',
      ]);
      final first = git.revParse(gitDir, 'HEAD')!;
      File(p.join(repo, 'f.txt')).writeAsStringSync('advanced');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'two',
      ]);
      final second = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: first);
      // The uncommitted work the refusal exists to protect — a person's own
      // edit, never landed anywhere else, standing only in this tree.
      final witness = File(p.join(where, 'f.txt'))
        ..writeAsStringSync('a person\'s uncommitted edit');

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isFalse);
      expect(result.report, isNotEmpty);
      // The claim is about the bytes, so the assert reads the bytes: no
      // remove-and-restand happened underneath the refusal, and the file
      // that would have been discarded by the old forced path is still
      // exactly what was written into it.
      expect(witness.readAsStringSync(), 'a person\'s uncommitted edit');
      expect(git.worktreeHead(where), first);
    });
  });

  group('worktreeDirtyPaths', () {
    test('a clean tree answers empty', () {
      final repo = enclosing('spotless');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);

      expect(git.worktreeDirtyPaths(where), isEmpty);
    });

    test('a modified tracked file appears', () {
      final repo = enclosing('modified');
      final gitDir = p.join(repo, '.git');
      File(p.join(repo, 'f.txt')).writeAsStringSync('base');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'one',
      ]);
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);
      File(p.join(where, 'f.txt')).writeAsStringSync('edited by hand');

      expect(git.worktreeDirtyPaths(where), ['f.txt']);
    });

    test('a staged file appears', () {
      final repo = enclosing('staged');
      final gitDir = p.join(repo, '.git');
      File(p.join(repo, 'f.txt')).writeAsStringSync('base');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'one',
      ]);
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);
      File(p.join(where, 'f.txt')).writeAsStringSync('staged edit');
      Process.runSync('git', ['-C', where, 'add', '.']);

      expect(git.worktreeDirtyPaths(where), ['f.txt']);
    });

    test('an untracked file appears, and names the path rather than prose',
        () {
      final repo = enclosing('untracked');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);
      File(p.join(where, 'new.txt')).writeAsStringSync('never committed');

      expect(git.worktreeDirtyPaths(where), ['new.txt']);
    });
  });
}
