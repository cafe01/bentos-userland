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
}
