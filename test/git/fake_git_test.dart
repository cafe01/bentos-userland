import 'dart:io';

import 'package:bentos_userland/entity.dart' show Action;
import 'package:bentos_userland/git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_git.dart';

/// **Infrastructure, proven.** The contract suite is red today and goes green
/// when construction fills the bodies in — which is only worth anything if the
/// collaborator underneath it was right all along. So the fake gets its own
/// green: the swap above all, because the entire action primitive rests on it.
///
/// This is not a test of the product. It is the test that lets the product's
/// tests be believed.
void main() {
  late FakeGit git;
  late Directory tmp;

  setUp(() {
    git = FakeGit();
    tmp = Directory.systemTemp.createTempSync('fake_git_test');
    git.init('/e.git');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String commitWith(Map<String, String> files, {Commit? parent}) {
    final wt = Directory(p.join(tmp.path, 'wt${files.hashCode}'))
      ..createSync(recursive: true);
    files.forEach((path, content) {
      File(p.join(wt.path, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    });
    final tree = git.writeTree('/e.git', workTree: wt.path);
    return git.commitTree(
      '/e.git',
      tree: tree,
      parents: [if (parent != null) parent.sha],
      message: Action.messageFor('prompt'),
      actor: Actor('alfred', email: 'alfred@test.local'),
    );
  }

  test('the same content always yields the same object name', () {
    final a = git.hashObject('/e.git', 'hello'.codeUnits);
    final b = git.hashObject('/e.git', 'hello'.codeUnits);
    final c = git.hashObject('/e.git', 'other'.codeUnits);
    expect(a, b);
    expect(a, isNot(c));
  });

  group('the compare-and-swap', () {
    test('a null expectation demands the ref not exist', () {
      final first = Commit(commitWith({'a.txt': 'one'}));
      expect(
        git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: first, expected: null).moved,
        isTrue,
      );
      final second = Commit(commitWith({'a.txt': 'two'}, parent: first));
      expect(
        git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: second, expected: null).moved,
        isFalse,
        reason: 'a first action must refuse to happen twice',
      );
    });

    test('exactly one of two writers reading the same tip lands', () {
      final base = Commit(commitWith({'a.txt': 'base'}));
      git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: base, expected: null);

      final mine = Commit(commitWith({'a.txt': 'mine'}, parent: base));
      final yours = Commit(commitWith({'a.txt': 'yours'}, parent: base));

      final firstLanded =
          git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: mine, expected: base);
      final secondLanded =
          git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: yours, expected: base);

      expect(firstLanded.moved, isTrue);
      expect(secondLanded.moved, isFalse);
      expect(git.revParse('/e.git', 'refs/heads/x'), mine);
    });
  });

  test('a diff is derived from two whole states', () {
    final one = Commit(commitWith({'a.txt': 'one', 'gone.txt': 'x'}));
    final two = Commit(commitWith({'a.txt': 'two', 'new.txt': 'y'}, parent: one));
    final diff = git.diffTree('/e.git', from: one, to: two);
    expect(diff.paths, ['a.txt', 'gone.txt', 'new.txt']);
    expect(
      diff.changes.map((c) => c.kind),
      [ChangeKind.modified, ChangeKind.deleted, ChangeKind.added],
    );
  });

  test('content is read at a ref with no worktree', () {
    final c = Commit(commitWith({'msg.txt': 'hello'}));
    git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: c, expected: null);
    expect(
      String.fromCharCodes(git.catFile('/e.git', 'refs/heads/x:msg.txt')),
      'hello',
    );
  });

  test('a clone answers with the refs and no worktree', () async {
    final c = Commit(commitWith({'a.txt': 'one'}));
    git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: c, expected: null);
    await git.clone('/e.git', '/site2.git');
    expect(git.revParse('/site2.git', 'refs/heads/x'), c);
    expect(git.repos['/site2.git']!.bare, isTrue);
  });

  test('the log walks the first-parent line, newest first', () {
    final one = Commit(commitWith({'a.txt': '1'}));
    final two = Commit(commitWith({'a.txt': '2'}, parent: one));
    git.updateRef('/e.git', ref: 'refs/heads/x', newCommit: two, expected: null);
    expect(
      git.log('/e.git', ref: 'refs/heads/x').map((c) => c.sha),
      [two.sha, one.sha],
    );
  });

  group('worktreeAdd', () {
    test('detached by default: no branch is recorded', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');

      git.worktreeAdd('/e.git', path: where, at: head);

      expect(git.currentBranch(where), isNull);
      expect(git.worktreeHead(where), head);
    });

    test('given a branch, the worktree stands attached to it', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');

      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');

      expect(git.currentBranch(where), 'feature');
      expect(git.worktreeHead(where), head);
    });

    test('attached, worktreeHead follows the branch past this call — the '
        'symref reading, not the sha this call happened to pass', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');

      final advanced = Commit(commitWith({'a.txt': 'two'}, parent: head));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: advanced, expected: head);

      expect(git.worktreeHead(where), advanced);
    });

    test('a second worktree is refused the branch the first already follows',
        () {
      // The double must agree with the substrate exactly at the point this
      // slice's law lives: a second attached tree on one branch is refused,
      // never modelled as legal.
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final first = p.join(tmp.path, 'first');
      final second = p.join(tmp.path, 'second');

      git.worktreeAdd('/e.git', path: first, at: head, branch: 'feature');

      expect(
        () => git.worktreeAdd('/e.git', path: second, at: head, branch: 'feature'),
        throwsA(isA<ProcessException>()),
      );
      expect(Directory(second).existsSync(), isFalse);
    });

    test('a directory whose registration outlived it does not block the add',
        () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');

      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');
      Directory(where).deleteSync(recursive: true);

      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');

      expect(git.currentBranch(where), 'feature');
    });
  });

  group('worktreesOn', () {
    test('nothing stands on a branch nobody attached to', () {
      expect(git.worktreesOn('/e.git', 'feature'), isEmpty);
    });

    test('a detached worktree at the same commit does not count', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head);

      expect(git.worktreesOn('/e.git', 'feature'), isEmpty);
    });

    test('one instance per branch, and a query never answers for a sibling',
        () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      git.updateRef('/e.git', ref: 'refs/heads/other', newCommit: head, expected: null);
      final second = p.join(tmp.path, 'aaa-other');
      final first = p.join(tmp.path, 'zzz-feature');

      git.worktreeAdd('/e.git', path: second, at: head, branch: 'other');
      git.worktreeAdd('/e.git', path: first, at: head, branch: 'feature');

      expect(git.worktreesOn('/e.git', 'feature'), [first]);
      expect(git.worktreesOn('/e.git', 'other'), [second]);
    });

    test('an unrelated branch is not named', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      git.updateRef('/e.git', ref: 'refs/heads/other', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');

      expect(git.worktreesOn('/e.git', 'other'), isEmpty);
    });

    test('removing an attached worktree drops it from the record', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      git.updateRef('/e.git', ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');

      git.worktreeRemove('/e.git', path: where);

      expect(git.worktreesOn('/e.git', 'feature'), isEmpty);
    });
  });

  group('worktreeCheckout', () {
    test('an unforced move brings the tree to the new commit', () {
      final first = Commit(commitWith({'a.txt': 'one'}));
      final second = Commit(commitWith({'a.txt': 'two'}, parent: first));
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: first);

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isTrue);
      expect(git.worktreeHead(where), second);
      expect(File(p.join(where, 'a.txt')).readAsStringSync(), 'two');
    });

    test('an untracked file the incoming tree never names survives the move',
        () {
      // The real port leaves a non-conflicting untracked file alone; a fake
      // that deletes-and-repopulates the whole directory destroys it instead
      // — silently, since nothing before this asserted the file was ever
      // there to begin with.
      final first = Commit(commitWith({'a.txt': 'one'}));
      final second = Commit(commitWith({'a.txt': 'two'}, parent: first));
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: first);
      final untracked = File(p.join(where, 'mine.txt'))
        ..writeAsStringSync('nobody landed this');

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isTrue);
      expect(untracked.readAsStringSync(), 'nobody landed this');
      expect(File(p.join(where, 'a.txt')).readAsStringSync(), 'two');
    });

    test('an untracked file the incoming tree would write refuses the move',
        () {
      final first = Commit(commitWith({'a.txt': 'one'}));
      final second =
          Commit(commitWith({'a.txt': 'one', 'new.txt': 'incoming'}, parent: first));
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: first);
      final collision = File(p.join(where, 'new.txt'))
        ..writeAsStringSync('a person\'s own file, never landed');

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isFalse);
      expect(result.report, isNotEmpty);
      expect(collision.readAsStringSync(), 'a person\'s own file, never landed');
      expect(git.worktreeHead(where), first);
    });

    test('a dirty tracked file declines, and its bytes survive the refusal',
        () {
      final first = Commit(commitWith({'a.txt': 'base'}));
      final second = Commit(commitWith({'a.txt': 'advanced'}, parent: first));
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: first);
      final witness = File(p.join(where, 'a.txt'))
        ..writeAsStringSync('a person\'s uncommitted edit');

      final result = git.worktreeCheckout(where, to: second);

      expect(result.moved, isFalse);
      expect(witness.readAsStringSync(), 'a person\'s uncommitted edit');
      expect(git.worktreeHead(where), first);
    });
  });

  /// The acting path, in the double — the same claims the real port answers,
  /// so that everything written above this line is written for one substrate
  /// and not two.
  group('commitInWorktree', () {
    /// A worktree attached to `feature`, standing at its tip.
    String attached(Commit head) {
      git.updateRef('/e.git',
          ref: 'refs/heads/feature', newCommit: head, expected: null);
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head, branch: 'feature');
      return where;
    }

    test('the branch moves because the commit happened in the tree', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      final where = attached(head);
      File(p.join(where, 'deposited.txt')).writeAsStringSync('the payload');

      final landed = git.commitInWorktree(
        where,
        message: Action.messageFor('prompt'),
        actor: Actor('alfred', email: 'alfred@test.local'),
      );

      expect(landed.commit, isNotNull);
      expect(git.revParse('/e.git', 'refs/heads/feature'), landed.commit);
      expect(git.revParse('/e.git', 'refs/heads/feature'), isNot(head));
      // Files, ref and record advance together, so nothing is left dirty —
      // the whole reason the act stopped being a swap from outside.
      expect(git.worktreeDirtyPaths(where), isEmpty);
      expect(git.showCommit('/e.git', landed.commit!).parents, [head.sha]);
    });

    test('a gate refuses, and the branch stands still', () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      final where = attached(head);
      File(p.join(where, 'deposited.txt')).writeAsStringSync('the payload');
      git.declineNextSwap = 'entity: refused by r4';

      final refused = git.commitInWorktree(
        where,
        message: Action.messageFor('prompt'),
        actor: Actor('alfred', email: 'alfred@test.local'),
      );

      expect(refused.commit, isNull);
      expect(refused.report, contains('refused by r4'));
      expect(git.revParse('/e.git', 'refs/heads/feature'), head);
    });

    test('a detached tree is refused: an act with no ref to move is orphaned',
        () {
      final head = Commit(commitWith({'a.txt': 'one'}));
      final where = p.join(tmp.path, 'loose');
      git.worktreeAdd('/e.git', path: where, at: head);

      expect(
        () => git.commitInWorktree(
          where,
          message: Action.messageFor('prompt'),
          actor: Actor('alfred', email: 'alfred@test.local'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('worktreeDiscard', () {
    test('tracked work is restored and untracked work is removed', () {
      final head = Commit(commitWith({'kept.txt': 'as committed'}));
      final where = p.join(tmp.path, 'standing');
      git.worktreeAdd('/e.git', path: where, at: head);
      File(p.join(where, 'kept.txt')).writeAsStringSync('written by the act');
      File(p.join(where, 'deposited.txt')).writeAsStringSync('written by the act');

      git.worktreeDiscard(where, to: head);

      expect(File(p.join(where, 'kept.txt')).readAsStringSync(), 'as committed');
      expect(File(p.join(where, 'deposited.txt')).existsSync(), isFalse);
      expect(git.worktreeDirtyPaths(where), isEmpty);
    });
  });
}
