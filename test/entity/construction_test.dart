import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The concrete port is not part of the public surface — a caller never names it,
// because the ambient already is it. Tier C is the one reader that must.
import 'package:bentos_userland/src/entity/git/process_git.dart';
import 'package:test/test.dart';

/// **Tier C — what only the real substrate can answer.**
///
/// Every test here is skipped, naming construction as the chair that unskips
/// it. They are written now, at design time, for one reason: these are the
/// questions a fake **cannot** be asked, and a suite that only asks the
/// answerable ones drifts into proving the double.
///
/// A green fake proves the model. Only these prove the machine.
const _owed = 'construction: real git, real repositories';

/// A worktree directory holding [files], for the verbs that take one.
String _stage(Directory scratch, Map<String, String> files) {
  final work = Directory('${scratch.path}/stage');
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);
  for (final entry in files.entries) {
    File('${work.path}/${entry.key}')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
  return work.path;
}

void main() {
  group('the port against the real substrate', () {
    const git = ProcessGit();
    late Directory scratch;
    late String gitDir;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('entity_real_');
      gitDir = '${scratch.path}/thing.git';
      git.init(gitDir);
    });

    tearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    /// One state committed onto [parent] and landed at [ref] — the plumbing
    /// quartet, spelled once, because every test below needs a history.
    Commit land(
      Map<String, String> files, {
      required String ref,
      Commit? parent,
      String message = 'write',
    }) {
      final work = Directory('${scratch.path}/work')
        ..createSync(recursive: true);
      for (final entry in files.entries) {
        File('${work.path}/${entry.key}')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(entry.value);
      }
      final tree = git.writeTree(gitDir, workTree: work.path);
      final sha = git.commitTree(
        gitDir,
        tree: tree,
        parents: [if (parent != null) parent.sha],
        message: message,
        actor: const Actor('alfred'),
      );
      expect(
        git.updateRef(gitDir,
            ref: ref, newCommit: Commit(sha), expected: parent),
        isTrue,
      );
      work.deleteSync(recursive: true);
      return Commit(sha);
    }

    test('a bare repository is created, and it is bare', () {
      expect(Directory('$gitDir/objects').existsSync(), isTrue);
      expect(Directory('$gitDir/.git').existsSync(), isFalse,
          reason: 'a bare repository has no nested .git');
      expect(
        File('$gitDir/config').readAsStringSync(),
        contains('bare = true'),
      );
    });

    test('the plumbing quartet writes a commit reachable by the real git', () {
      final tip = land({'greeting': 'hello\n'}, ref: 'refs/heads/one');

      expect(git.revParse(gitDir, 'refs/heads/one'), equals(tip));
      expect(git.branches(gitDir), equals(['one']));

      final record = git.showCommit(gitDir, tip);
      expect(record.sha, equals(tip.sha));
      expect(record.parents, isEmpty);
      expect(record.author.name, equals('alfred'));
      expect(record.message.trim(), equals('write'));

      // The state is read at the ref, with no worktree anywhere.
      expect(
        utf8.decode(git.catFile(gitDir, '${tip.sha}:greeting')),
        equals('hello\n'),
      );
    });

    test('update-ref with a stale expectation is refused by git itself', () {
      final first = land({'a': '1\n'}, ref: 'refs/heads/one');
      final second =
          land({'a': '2\n'}, ref: 'refs/heads/one', parent: first, message: 'again');

      // A second actor that read the tip at `first` and writes now: the object
      // exists, and only the swap is still in question.
      final tree = git.writeTree(gitDir, workTree: _stage(scratch, {'a': '3\n'}));
      final stale = Commit(git.commitTree(
        gitDir,
        tree: tree,
        parents: [first.sha],
        message: 'loser',
      ));

      expect(
        git.updateRef(gitDir,
            ref: 'refs/heads/one', newCommit: stale, expected: first),
        isFalse,
        reason: 'the tip moved under the loser',
      );
      expect(git.revParse(gitDir, 'refs/heads/one'), equals(second));

      // Refusal leaves no residue on the ref, and the object still exists —
      // orphaned, which is what makes `.refused` readable.
      expect(git.showCommit(gitDir, stale).message.trim(), equals('loser'));
    });

    test('an empty expectation refuses a ref that already exists', () {
      final tip = land({'a': '1\n'}, ref: 'refs/heads/one');

      final tree = git.writeTree(gitDir, workTree: _stage(scratch, {'a': '2\n'}));
      final twice = Commit(git.commitTree(
        gitDir,
        tree: tree,
        parents: const [],
        message: 'a first action, twice',
      ));

      expect(
        git.updateRef(gitDir,
            ref: 'refs/heads/one', newCommit: twice, expected: null),
        isFalse,
        reason: 'a null expectation means the ref must not exist',
      );
      expect(git.revParse(gitDir, 'refs/heads/one'), equals(tip));

      // The same swap on a name nobody holds is how a first action lands.
      expect(
        git.updateRef(gitDir,
            ref: 'refs/heads/two', newCommit: twice, expected: null),
        isTrue,
      );
    });

    test('a worktree shares the object store with the entity', () {
      final tip = land({'greeting': 'hello\n'}, ref: 'refs/heads/one');
      final at = '${scratch.path}/look';

      git.worktreeAdd(gitDir, path: at, at: tip);
      expect(File('$at/greeting').readAsStringSync(), equals('hello\n'));

      // Shared, not copied: the worktree carries a pointer file, never a store
      // of its own.
      expect(Directory('$at/.git').existsSync(), isFalse);
      expect(File('$at/.git').readAsStringSync(), contains('gitdir:'));
      expect(Directory('$at/.git/objects').existsSync(), isFalse);

      git.worktreeRemove(gitDir, path: at);
      expect(Directory(at).existsSync(), isFalse);
      // Deregistered, not merely deleted — the leak the API exists to prevent.
      expect(
        Directory('$gitDir/worktrees').existsSync() &&
            Directory('$gitDir/worktrees').listSync().isNotEmpty,
        isFalse,
      );
    });

  });

  group('the shim, mounted for real', () {
    test('git runs the hook out of the common dir, even from a worktree', () {},
        skip: _owed);

    test('a refusing listener aborts the real ref update, and the tip is unmoved',
        () {}, skip: _owed);

    test('the action noun is read back off a real commit object', () {},
        skip: _owed);

    test('a landing wakes a subscriber that outlives the git process', () {},
        skip: _owed);
  });

  group('federation — the axis no other gate varies', () {
    // Four gates of the PoC varied the state inside one machine and all
    // passed; the fifth varied the machine, and was the only one that could
    // expose a locality dependency. It found one on its first run.
    test('a clone arms differently and reacts to a pushed act', () {}, skip: _owed);

    test('the receiving side runs its own hook on push', () {}, skip: _owed);

    test('a site that only reacts holds no worktree and still reads state', () {},
        skip: _owed);
  });

  group('acceptance', () {
    // The lab's `bash test/gates.sh` walks the whole vocabulary of
    // `bentos.llm` on raw Git — five gates, twenty-three assertions, no API
    // key. Construction promotes it: the same gates, driven through the
    // `entity` coreutil instead of hand-spelled shell, is the acceptance proof
    // that the primitive absorbed the PoC without losing a property.
    //
    // Source: `lab/entity/test/gates.sh` · promotion list: `lab/entity/PROMOTION.md`
    test('the lab gates pass driven through the entity coreutil', () {},
        skip: 'construction: promote lab/entity/test/gates.sh');
  });
}
