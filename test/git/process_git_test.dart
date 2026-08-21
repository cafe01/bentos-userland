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

  group('worktreeAdd', () {
    test('detached by default: no branch, and HEAD is a plain commit',
        () async {
      final repo = enclosing('bare-attach');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');

      git.worktreeAdd(gitDir, path: where, at: head);

      expect(git.currentBranch(where), isNull);
      expect(git.worktreeHead(where), head);
    });

    test('given a branch, the worktree stands attached to it', () async {
      final repo = enclosing('attach');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      final where = p.join(scratch.path, 'standing');

      git.worktreeAdd(gitDir, path: where, at: head, branch: 'feature');

      expect(git.currentBranch(where), 'feature');
      expect(git.worktreeHead(where), head);
    });

    test('an ordinary commit inside an attached worktree moves the branch',
        () async {
      final repo = enclosing('attach-commit');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head, branch: 'feature');

      File(p.join(where, 'f.txt')).writeAsStringSync('one');
      Process.runSync('git', ['-C', where, 'add', '.']);
      Process.runSync('git', [
        '-C', where,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'two',
      ]);

      final advanced = git.revParse(gitDir, 'refs/heads/feature');
      expect(advanced, isNot(head));
      expect(git.worktreeHead(where), advanced);
    });

    test('several worktrees may stand attached to the same branch at once',
        () async {
      final repo = enclosing('two-lookers');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      final first = p.join(scratch.path, 'first');
      final second = p.join(scratch.path, 'second');

      git.worktreeAdd(gitDir, path: first, at: head, branch: 'feature');
      git.worktreeAdd(gitDir, path: second, at: head, branch: 'feature');

      expect(git.currentBranch(first), 'feature');
      expect(git.currentBranch(second), 'feature');
    });
  });

  group('worktreesOn', () {
    test('nothing stands on a branch nobody attached to', () async {
      final repo = enclosing('none-standing');
      final gitDir = p.join(repo, '.git');

      expect(git.worktreesOn(gitDir, 'feature'), isEmpty);
    });

    test('a detached worktree at the same commit does not count', () async {
      final repo = enclosing('detached-only');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);

      expect(git.worktreesOn(gitDir, 'feature'), isEmpty);
    });

    test('names every attached worktree, sorted', () async {
      final repo = enclosing('several-standing');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      final second = p.join(scratch.path, 'zzz-second');
      final first = p.join(scratch.path, 'aaa-first');

      git.worktreeAdd(gitDir, path: second, at: head, branch: 'feature');
      git.worktreeAdd(gitDir, path: first, at: head, branch: 'feature');

      expect(git.worktreesOn(gitDir, 'feature'), [first, second]);
    });

    test('an unrelated branch is not named', () async {
      final repo = enclosing('unrelated-branch');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      Process.runSync('git', ['-C', repo, 'branch', 'feature', head.sha]);
      Process.runSync('git', ['-C', repo, 'branch', 'other', head.sha]);
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head, branch: 'feature');

      expect(git.worktreesOn(gitDir, 'other'), isEmpty);
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

  /// The act, at the port. The fake cannot answer any of it: a commit made
  /// inside a worktree moves the branch through Git's own transaction, and a
  /// `reference-transaction` hook is the substrate's, not a model's.
  group('commitInWorktree', () {
    const actor = Actor.new;

    /// What Git recorded as author and committer of one commit.
    (String, String) signersOf(String repo, String sha) {
      final out = Process.runSync(
        'git',
        ['-C', repo, 'log', '-1', '--format=%an <%ae>%n%cn <%ce>', sha],
      ).stdout.toString().trim().split('\n');
      return (out[0], out[1]);
    }

    /// A worktree attached to a branch of [repo], standing at its tip.
    String attached(String repo, String branch) {
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      git.branch(gitDir, name: branch, startPoint: head);
      final where = p.join(scratch.path, 'standing-$branch');
      git.worktreeAdd(gitDir, path: where, at: head, branch: branch);
      return where;
    }

    test('the branch moves because the commit happened in the tree', () {
      final repo = enclosing('acting');
      final gitDir = p.join(repo, '.git');
      final where = attached(repo, 'demo');
      final before = git.revParse(gitDir, 'refs/heads/demo')!;
      File(p.join(where, 'deposited.txt')).writeAsStringSync('the payload');

      final landed = git.commitInWorktree(
        where,
        message: 'one act',
        actor: actor('alfred', email: 'alfred@bentos'),
      );

      expect(landed.commit, isNotNull);
      expect(landed.report, isEmpty);
      // The ref moved, and to exactly what landed — no swap asked for it.
      expect(git.revParse(gitDir, 'refs/heads/demo'), landed.commit);
      expect(git.revParse(gitDir, 'refs/heads/demo'), isNot(before));
      // And the three agree: files, index and ref, with nothing left over.
      expect(git.worktreeDirtyPaths(where), isEmpty);
    });

    test('an empty act lands — the payload is nobody\'s judgment down here',
        () {
      final repo = enclosing('empty-act');
      final gitDir = p.join(repo, '.git');
      final where = attached(repo, 'demo');

      final landed = git.commitInWorktree(
        where,
        message: 'deposited nothing',
        actor: actor('alfred', email: 'alfred@bentos'),
      );

      expect(landed.commit, isNotNull);
      expect(git.revParse(gitDir, 'refs/heads/demo'), landed.commit);
    });

    test('the actor signs both halves, with the cascade configured against it',
        () {
      final repo = enclosing('signed');
      // The cascade, reachable and answering — which is exactly the machine
      // owner a being's commits used to be signed as.
      Process.runSync('git', ['-C', repo, 'config', 'user.name', 'the machine']);
      Process.runSync(
          'git', ['-C', repo, 'config', 'user.email', 'owner@workstation']);
      final where = attached(repo, 'demo');
      File(p.join(where, 'f.txt')).writeAsStringSync('x');

      final landed = git.commitInWorktree(
        where,
        message: 'signed act',
        actor: actor('alfred', email: 'alfred@bentos'),
      );

      expect(
        signersOf(repo, landed.commit!.sha),
        ('alfred <alfred@bentos>', 'alfred <alfred@bentos>'),
      );
    });

    test('a gate at reference-transaction refuses, and the branch stands still',
        () {
      final repo = enclosing('gated');
      final gitDir = p.join(repo, '.git');
      final where = attached(repo, 'demo');
      final before = git.revParse(gitDir, 'refs/heads/demo')!;
      final hooks = Directory(p.join(gitDir, 'hooks'))..createSync(recursive: true);
      File(p.join(hooks.path, 'reference-transaction'))
        ..writeAsStringSync('#!/bin/sh\n'
            '[ "\$1" = prepared ] || exit 0\n'
            'echo "entity: refused by r4" >&2\n'
            'exit 1\n')
        ..setLastModifiedSync(DateTime.now());
      Process.runSync(
          'chmod', ['+x', p.join(hooks.path, 'reference-transaction')]);
      File(p.join(where, 'f.txt')).writeAsStringSync('x');

      final refused = git.commitInWorktree(
        where,
        message: 'barred act',
        actor: actor('alfred', email: 'alfred@bentos'),
      );

      expect(refused.commit, isNull);
      expect(refused.report, contains('refused by r4'));
      expect(git.revParse(gitDir, 'refs/heads/demo'), before);
    });

    test('a detached tree is refused here, because Git itself would not', () {
      final repo = enclosing('detached');
      final gitDir = p.join(repo, '.git');
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'loose');
      git.worktreeAdd(gitDir, path: where, at: head);
      File(p.join(where, 'f.txt')).writeAsStringSync('x');

      expect(
        () => git.commitInWorktree(
          where,
          message: 'nowhere',
          actor: actor('alfred', email: 'alfred@bentos'),
        ),
        throwsA(isA<StateError>()),
      );
      // The point of the refusal: nothing was staged, nothing was written,
      // and no object was left behind for nobody to hold.
      expect(git.worktreeDirtyPaths(where), ['f.txt']);
    });
  });

  group('worktreeDiscard', () {
    test('tracked work is restored and untracked work is removed', () {
      final repo = enclosing('discarding');
      final gitDir = p.join(repo, '.git');
      File(p.join(repo, 'kept.txt')).writeAsStringSync('as committed');
      Process.runSync('git', ['-C', repo, 'add', '.']);
      Process.runSync('git', [
        '-C', repo,
        '-c', 'user.email=gate@bentos',
        '-c', 'user.name=gate',
        'commit', '--quiet', '-m', 'base',
      ]);
      final head = git.revParse(gitDir, 'HEAD')!;
      final where = p.join(scratch.path, 'standing');
      git.worktreeAdd(gitDir, path: where, at: head);
      File(p.join(where, 'kept.txt')).writeAsStringSync('written by the act');
      File(p.join(where, 'deposited.txt')).writeAsStringSync('written by the act');
      Process.runSync('git', ['-C', where, 'add', '.']);

      git.worktreeDiscard(where, to: head);

      expect(File(p.join(where, 'kept.txt')).readAsStringSync(), 'as committed');
      expect(File(p.join(where, 'deposited.txt')).existsSync(), isFalse);
      expect(git.worktreeDirtyPaths(where), isEmpty);
    });
  });

  /// The fake cannot answer this: a refspec is a claim about what the real
  /// substrate does on the next fetch, and only the real one fetches.
  group('a bare clone can answer where it stands', () {
    test('a fetch writes remote-tracking refs, so standing needs no network',
        () async {
      final upstream = enclosing('upstream');
      final gitDir = p.join(scratch.path, 'copy.git');

      await git.clone(upstream, gitDir);
      // The claim is not that a config key holds a string. It is that a fetch
      // now populates `refs/remotes/*` — which is what makes an upstream, and
      // therefore ahead/behind, expressible at all.
      Process.runSync('git', ['--git-dir=$gitDir', 'fetch', 'origin']);

      final tracking = Process.runSync('git', [
        '--git-dir=$gitDir',
        'for-each-ref',
        '--format=%(refname)',
        'refs/remotes',
      ]).stdout as String;
      expect(tracking, contains('refs/remotes/origin/'));
    });

    test('the copy reads its own distance from the source, offline', () async {
      final upstream = enclosing('source');
      final gitDir = p.join(scratch.path, 'behind.git');
      await git.clone(upstream, gitDir);

      final branch = Process.runSync('git', [
        '--git-dir=$gitDir',
        'symbolic-ref',
        '--short',
        'HEAD',
      ]).stdout.toString().trim();
      Process.runSync('git', ['--git-dir=$gitDir', 'fetch', 'origin']);
      Process.runSync('git', [
        '--git-dir=$gitDir',
        'config',
        'branch.$branch.remote',
        'origin',
      ]);
      Process.runSync('git', [
        '--git-dir=$gitDir',
        'config',
        'branch.$branch.merge',
        'refs/heads/$branch',
      ]);

      // Two commits land at the source and are fetched; nothing merges them.
      for (final m in ['two', 'three']) {
        Process.runSync('git', [
          '-C', upstream,
          '-c', 'user.email=gate@bentos',
          '-c', 'user.name=gate',
          'commit', '--quiet', '--allow-empty', '-m', m,
        ]);
      }
      Process.runSync('git', ['--git-dir=$gitDir', 'fetch', 'origin']);

      final track = Process.runSync('git', [
        '--git-dir=$gitDir',
        'for-each-ref',
        '--format=%(upstream:track)',
        'refs/heads/$branch',
      ]).stdout.toString().trim();
      expect(track, '[behind 2]');
    });
  });
}
