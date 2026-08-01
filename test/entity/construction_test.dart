import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The concrete port is not part of the public surface — a caller never names it,
// because the ambient already is it. Tier C is the one reader that must.
import 'package:bentos_userland/src/entity/git/process_git.dart';
import 'package:test/test.dart';

import 'helpers.dart';

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

/// A real place on disk. No port is installed around it: above this line the
/// ambient already **is** [ProcessGit], which is the whole point of Tier C.
Directory _place(String label) {
  final root = Directory.systemTemp.createTempSync(label);
  Directory('${root.path}/.place').createSync(recursive: true);
  File('${root.path}/.place/place.yaml').writeAsStringSync('name: $label\n');
  return root;
}

/// A listener: a real program on disk, mode 755, called by the shim as
/// `<cmd> <repo> <ref> <old> <new> <action>`.
String _listener(Directory site, String name, String body) {
  final file = File('${site.path}/$name.sh')
    ..writeAsStringSync('#!/usr/bin/env bash\n$body\n');
  Process.runSync('chmod', ['755', file.path]);
  return file.path;
}

/// Waits for a detached subscriber's artifact. A `.landed` listener is woken
/// with `nohup … &`, so the only honest proof it ran is the disk — never the
/// return of the process that woke it.
Future<void> _settles(
  File artifact, {
  Duration within = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(within);
  while (DateTime.now().isBefore(deadline)) {
    if (artifact.existsSync() && artifact.lengthSync() > 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('the subscriber left nothing at ${artifact.path} within $within');
}

/// A commit object over [files], parented at [parent], written into the entity's
/// own repository and **not landed**. The swap is what the caller is about to
/// perform by hand, from somewhere of its choosing.
Commit _commitOnto(
  Directory site,
  Entity entity,
  Map<String, String> files, {
  required Commit parent,
}) {
  const git = ProcessGit();
  final gitDir = repositoryOf(site.path, entity.name);
  final tree = git.writeTree(gitDir, workTree: _stage(site, files));
  return Commit(git.commitTree(
    gitDir,
    tree: tree,
    parents: [parent.sha],
    message: Action.messageFor('note'),
    actor: const Actor('alfred'),
  ));
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

    test('a poisoned environment does not move the port off its repository', () {
      // The debt this closes: every invocation is told where to work by
      // argument, so any `GIT_*` surviving in the environment is a lie waiting
      // to be believed — and the failure is silent, bytes landing in a
      // repository nobody named. `Platform.environment` is fixed for the life of
      // a process, so the only honest proof is a child born dirty.
      final decoy = '${scratch.path}/decoy.git';
      git.init(decoy);
      land({'a': '1\n'}, ref: 'refs/heads/one');

      final child = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'test/entity/tools/poisoned_port.dart', gitDir, 'refs/heads/one'],
        workingDirectory: Directory.current.path,
        environment: {
          'GIT_DIR': decoy,
          'GIT_COMMON_DIR': decoy,
          'GIT_WORK_TREE': scratch.path,
          'GIT_INDEX_FILE': '$decoy/index',
          'GIT_OBJECT_DIRECTORY': '$decoy/objects',
          'GIT_ALTERNATE_OBJECT_DIRECTORIES': '$decoy/objects',
          'GIT_QUARANTINE_PATH': '$decoy/quarantine',
          'GIT_PREFIX': 'nowhere/',
        },
      );
      expect(child.exitCode, isZero, reason: '${child.stderr}');

      final landed = Commit((child.stdout as String).trim());
      expect(git.revParse(gitDir, 'refs/heads/one'), equals(landed));
      // The object is in the entity's own store, not the one the environment
      // named — the assertion that would fail silently without the scrub.
      expect(
        utf8.decode(git.catFile(gitDir, '${landed.sha}:note')),
        equals('written under a lie\n'),
      );
      expect(git.branches(decoy), isEmpty, reason: 'the decoy was never written');
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
    late Directory site;
    late Entity thing;
    late Instance one;
    late File witness;

    setUp(() {
      site = _place('entity_shim_');
      thing = Entity('t.thing', from: site.path).create();
      one = thing.instance('one').create();
      witness = File('${site.path}/witness');
    });

    tearDown(() {
      if (site.existsSync()) site.deleteSync(recursive: true);
    });

    test('git runs the hook out of the common dir, even from a worktree', () async {
      // The listener records the repository the shim handed it. That argument is
      // `dirname $0/..`, so what lands in the witness is the shim's own answer to
      // *where am I* — the whole question.
      thing.on(
        {const EventPattern(action: '*', phase: EventPhase.landed)},
        command: [_listener(site, 'record', 'printf "%s\\n" "\$1" >> "${witness.path}"')],
      );

      // A materialization is a worktree with a private git dir of its own. The
      // update is made from inside it, by the real git, which is the only way to
      // ask the question: a shim that asked git instead of locating itself would
      // resolve to that private dir, find no table, and say nothing.
      final face = one.materialize();
      final from = one.tip!;
      final next = _commitOnto(site, thing, {'a': '1\n'}, parent: from);
      final update = Process.runSync(
        'git',
        ['update-ref', one.ref, next.sha, from.sha],
        workingDirectory: face.directory.path,
      );
      expect(update.exitCode, isZero, reason: update.stderr.toString());
      face.release();

      await _settles(witness);
      expect(
        witness.readAsStringSync().trim(),
        equals(repositoryOf(site.path, thing.name)),
        reason: 'the shim must answer with the common directory, not a worktree',
      );
    });

    test('a refusing listener aborts the real ref update, and the tip is unmoved',
        () async {
      thing.on(
        {const EventPattern(action: '*', phase: EventPhase.attempted)},
        command: [_listener(site, 'refuse', 'exit 1')],
      );
      final standing = one.tip;

      final result = await one.act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('hello\n');
      });

      expect(result, isA<Refused>());
      expect(one.tip, equals(standing), reason: 'nothing was ever true');
      // Refusal leaves no residue on the ref and the object survives, orphaned —
      // which is what makes a `.refused` payload readable at all.
      expect(one.log, isEmpty);
    });

    test('the action noun is read back off a real commit object', () async {
      // The shim reads the trailer with `cat-file | sed`, and the noun is what a
      // subscription matches on. This is the proof that the two halves — the
      // trailer Dart writes and the parse the shell does — meet.
      thing.on(
        {const EventPattern(action: 'reply', phase: EventPhase.landed)},
        command: [_listener(site, 'noun', 'printf "%s\\n" "\$5" >> "${witness.path}"')],
      );

      final result = await one.act('reply', (workspace) {
        File('${workspace.directory.path}/said').writeAsStringSync('hi\n');
      });
      expect(result, isA<Landed>());

      await _settles(witness);
      expect(witness.readAsStringSync().trim(), equals('reply'));
    });

    test('a landing wakes a subscriber that outlives the git process', () async {
      // A landing is never held hostage to what it wakes: the listener sleeps
      // past every process in the chain, and the act returns without it.
      thing.on(
        {const EventPattern(action: '*', phase: EventPhase.landed)},
        command: [
          _listener(site, 'slow', 'sleep 1; printf "%s\\n" "\$4" >> "${witness.path}"'),
        ],
      );

      final result = await one.act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('hello\n');
      });
      expect(result, isA<Landed>());
      expect(witness.existsSync(), isFalse,
          reason: 'the act returned before its subscriber did');

      await _settles(witness, within: const Duration(seconds: 10));
      expect(
        witness.readAsStringSync().trim(),
        equals((result as Landed).action.commit.sha),
      );
    });
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
