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

    test('the machine never answers — with the cascade configured and reachable',
        () {
      final (repo, tree) = groundOf('cascade');

      // **The control, asserted rather than assumed.** An absent cascade
      // over-determines everything below it: the identity could not have been
      // taken from the machine because there was nothing there to take. So the
      // gate first proves the machine *does* have an answer, and a good one —
      // then proves nothing reaches for it.
      final configured = Process.runSync('git', ['-C', repo, 'config', 'user.email']);
      expect(configured.exitCode, 0,
          reason: 'the cascade must be reachable, or this gate proves nothing');
      expect(configured.stdout.toString().trim(), 'gate@bentos');

      final made = git.commitTree(
        p.join(repo, '.git'),
        tree: tree,
        parents: [],
        message: 'two',
        actor: Actor('alfred', email: 'alfred@bentos.life'),
      );

      expect(authorOf(repo, made), 'alfred <alfred@bentos.life>');
      expect(authorOf(repo, made), isNot(contains('gate')),
          reason: 'the workstation owner is not who acted');
    });

    test('an unsigned commit is not expressible at this port', () {
      // No assertion, because there is nothing left to assert against: the
      // parameter is required, so the call that produced the old defect does
      // not compile. A grep is a weak witness for behaviour and a perfectly
      // good one for deletion — and the type system is a stronger one still.
      expect(
        () => Actor('alfred', email: ''),
        throwsArgumentError,
        reason: 'nor may a half-stated identity reach a commit',
      );
      expect(() => Actor('', email: 'a@b'), throwsArgumentError);
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
