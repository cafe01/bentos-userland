import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The concrete port is not part of the public surface — a caller never names it,
// because the ambient already is it. Tier C is the one reader that must.
import 'package:bentos_userland/src/git/process_git.dart';
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
  // Resolved: a place answers with its canonical root, so the habitat states
  // which spelling it stands in rather than inheriting the system temp's.
  final root = Directory(
      Directory.systemTemp.createTempSync(label).resolveSymbolicLinksSync());
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
                ref: ref, newCommit: Commit(sha), expected: parent)
            .moved,
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

    test('ls-tree lists one level at a commit, and the fake agrees', () {
      final first = land(
        {'messages/0001.txt': 'a\n', 'meta/card.json': '{}\n'},
        ref: 'refs/heads/one',
      );
      land(
        {
          'messages/0001.txt': 'a\n',
          'messages/0002.txt': 'b\n',
          'meta/card.json': '{}\n',
        },
        ref: 'refs/heads/one',
        parent: first,
      );
      final tip = git.revParse(gitDir, 'refs/heads/one')!;

      expect(
        git.lsTree(gitDir, at: tip, path: 'messages'),
        equals(['messages/0001.txt', 'messages/0002.txt']),
      );
      // The root lists entries and not the tree beneath them — the reading is
      // one level deep, exactly as `ls` is.
      expect(
        git.lsTree(gitDir, at: tip, path: ''),
        equals(['messages', 'meta']),
      );
      // At an earlier point the answer is different, which is the whole reason
      // the reading takes a commit.
      expect(
        git.lsTree(gitDir, at: first, path: 'messages'),
        equals(['messages/0001.txt']),
      );
      expect(git.lsTree(gitDir, at: tip, path: 'nowhere'), isEmpty);
    });

    test('a worktree reports what it stands at, and it is not the ref', () {
      final first = land({'a': '1\n'}, ref: 'refs/heads/one');
      final path = '${scratch.path}/face';
      git.worktreeAdd(gitDir, path: path, at: first);

      expect(git.worktreeHead(path), equals(first));
      expect(git.worktreeRepository(path), isNotNull);

      // The ref moves and the files do not. What a face stands at is a fact
      // about the looker's own last act, which is why it must be asked of the
      // tree — the repository's own head is another question entirely.
      final second = land({'a': '2\n'}, ref: 'refs/heads/one', parent: first);
      expect(git.worktreeHead(path), equals(first),
          reason: 'a materialization lags, and says so');
      expect(git.revParse(gitDir, 'refs/heads/one'), equals(second));

      git.worktreeRemove(gitDir, path: path);
      expect(git.worktreeHead(path), isNull,
          reason: 'nothing stands there any more');
    });

    test('is-ancestor separates a line extended from two lines diverged', () {
      final root = land({'a': '1\n'}, ref: 'refs/heads/one');
      final ahead = land({'a': '2\n'}, ref: 'refs/heads/one', parent: root);
      // A sibling off the same parent: neither line contains the other. The
      // second ref is pointed at the shared parent first, exactly as a fork is.
      git.branch(gitDir, name: 'two', startPoint: root);
      final sibling = land({'a': '3\n'}, ref: 'refs/heads/two', parent: root);

      expect(git.isAncestor(gitDir, ancestor: root, descendant: ahead), isTrue);
      expect(git.isAncestor(gitDir, ancestor: ahead, descendant: root), isFalse,
          reason: 'behind is not ahead');
      expect(git.isAncestor(gitDir, ancestor: ahead, descendant: sibling), isFalse);
      expect(git.isAncestor(gitDir, ancestor: root, descendant: root), isTrue,
          reason: 'a commit is its own ancestor, and fetching it changes nothing');
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

      final lost = git.updateRef(gitDir,
          ref: 'refs/heads/one', newCommit: stale, expected: first);
      expect(lost.moved, isFalse, reason: 'the tip moved under the loser');
      // **The evidence survives the port.** This half of the disjoint pair is
      // what a lost race says, and the word that is absent from it is the whole
      // discriminator: a gate's refusal, the other half, is the same `false`
      // over `ref updates aborted by hook`. A port answering a bare bool made
      // the floor above guess, and the guess printed `expected b71043a, found
      // b71043a` at a ref nothing had moved.
      expect(lost.report, contains('cannot lock ref'));
      expect(lost.report, isNot(contains('hook')));
      expect(
        git.updateRef(gitDir,
                ref: 'refs/heads/three', newCommit: stale, expected: null)
            .report,
        isEmpty,
        reason: 'a swap that moved has nothing to report',
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
                ref: 'refs/heads/one', newCommit: twice, expected: null)
            .moved,
        isFalse,
        reason: 'a null expectation means the ref must not exist',
      );
      expect(git.revParse(gitDir, 'refs/heads/one'), equals(tip));

      // The same swap on a name nobody holds is how a first action lands.
      expect(
        git.updateRef(gitDir,
                ref: 'refs/heads/two', newCommit: twice, expected: null)
            .moved,
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

    test('an unresolvable entity refuses the transaction rather than admitting it '
        'silently', () {
      // The falsifier for the contract clause worth having most: the trampoline
      // depends on `entity` being resolvable on PATH at hook time, and a
      // publisher that cannot reach the primitive must refuse rather than let an
      // unvalidated act through. Proven by starving the shim of the one thing it
      // execs, over a real transaction — never by reading the shim's own source.
      final from = one.tip!;
      final next = _commitOnto(site, thing, {'b': '1\n'}, parent: from);
      final update = Process.runSync(
        'git',
        ['--git-dir', repositoryOf(site.path, thing.name), 'update-ref',
          one.ref, next.sha, from.sha],
        environment: {'PATH': '/usr/bin:/bin'},
      );
      expect(update.exitCode, isNot(0),
          reason: 'an unresolvable entity must abort the transaction, not '
              'admit it silently');
      expect(update.stderr.toString(), contains('entity'),
          reason: "the shell's own account of the failed exec reaches Git");
      expect(one.tip, equals(from),
          reason: 'nothing was ever true — the same law a refusing gate proves');
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

      expect(result, isA<Barred>());
      expect(one.tip, equals(standing), reason: 'nothing was ever true');
      // Refusal leaves no residue on the ref and the object survives, orphaned —
      // which is what makes a `.refused` payload readable at all.
      expect(one.log(), isEmpty);
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

    test('a once line fires on the real substrate and is gone', () async {
      // The axis neither other tier varies: a real repository, the real git
      // transaction, and a line that must remove itself from a table the hook
      // is reading at that instant.
      final armed = thing.once(
        {const EventPattern(action: '*', phase: EventPhase.landed)},
        command: [_listener(site, 'onceling', 'printf "%s\\n" "\$5" >> "${witness.path}"')],
      );

      expect(await one.act('note', (w) {
        File('${w.directory.path}/a').writeAsStringSync('1\n');
      }), isA<Landed>());
      await _settles(witness);
      expect(witness.readAsStringSync().trim(), 'note');
      expect(thing.listeners.map((l) => l.id), isNot(contains(armed.id)));

      expect(await one.act('note2', (w) {
        File('${w.directory.path}/b').writeAsStringSync('2\n');
      }), isA<Landed>());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        witness.readAsStringSync().trim(),
        'note',
        reason: 'the second landing found nothing armed',
      );
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
    late Directory here;
    late Directory there;
    late Entity mine;
    late Instance one;

    setUp(() async {
      here = _place('entity_here_');
      there = _place('entity_there_');
      mine = Entity('t.thing', from: here.path).create();
      one = mine.instance('one').create();
      // One act before the clone, so the other site is born holding a past.
      final first = await one.act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('first\n');
      });
      expect(first, isA<Landed>());
      await Entity.install(repositoryOf(here.path, mine.name), at: there.path);
    });

    tearDown(() {
      for (final dir in [here, there]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    Entity theirs() => Entity('t.thing', from: there.path);

    test('a clone arms differently and reacts to a pushed act', () async {
      // **Arming is per installation** — beside the repository, outside every
      // tree, never cloned. So a clone arrives inert, and one line of difference
      // is the whole distance between a site that watches and a site that works.
      expect(theirs().listeners, isEmpty, reason: 'arming does not travel');

      final witness = File('${there.path}/witness');
      theirs().on(
        {const EventPattern(action: '*', phase: EventPhase.landed)},
        command: [_listener(there, 'record', 'printf "%s\\n" "\$4" >> "${witness.path}"')],
      );
      expect(theirs().listeners, hasLength(1));
      expect(mine.listeners, isEmpty, reason: 'this site never armed anything');

      final landed = await one.act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('second\n');
      }) as Landed;
      // The act landed here and woke nothing here — the other site is where the
      // reaction lives.
      expect(File('${here.path}/witness').existsSync(), isFalse);

      await mine.publish(repositoryOf(there.path, mine.name));

      await _settles(witness);
      expect(witness.readAsStringSync().trim(), equals(landed.action.commit.sha));
      expect(theirs().instance('one').tip, equals(landed.action.commit));
    });

    test('the receiving side runs its own hook on push', () async {
      // Federation is not a second mechanism: the receiving side runs the same
      // shim at the same phase, so a site may refuse what another site landed —
      // and the refusal is the substrate's own, not a protocol we invented.
      theirs().on(
        {const EventPattern(action: '*', phase: EventPhase.attempted)},
        command: [_listener(there, 'refuse', 'exit 1')],
      );
      final standing = theirs().instance('one').tip;

      final landed = await one.act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('second\n');
      }) as Landed;

      await expectLater(
        mine.publish(repositoryOf(there.path, mine.name)),
        throwsA(isA<ProcessException>()),
        reason: 'the receiving side declined the update',
      );
      expect(theirs().instance('one').tip, equals(standing),
          reason: 'nothing became true there');
      expect(one.tip, equals(landed.action.commit),
          reason: 'and it stays true here — the two lines are participants');
    });

    test('a site that only reacts holds no worktree and still reads state', () async {
      // Install does not materialize. A federated site that only reacts holds no
      // worktree at all, and reading at the ref is what it lives on.
      expect(Directory('${there.path}/${mine.name}').existsSync(), isFalse,
          reason: 'nothing was checked out into the place tree');

      expect(
        utf8.decode(theirs().instance('one').read('note')),
        equals('first\n'),
      );
      // And it knows what it holds without looking at a file: the class, its
      // objects, and their acts, all read at the refs.
      expect([for (final i in theirs().instances) i.id], equals(['one']));
      expect(theirs().instance('one').log().single.name, equals('note'));
    });

    test('fetch brings the other site\'s line down and advances the ref', () async {
      // The mirror of push. The act is taken over *there*, and this site — which
      // pushed nothing and was told nothing — brings it home.
      final landed = await theirs().instance('one').act('note', (workspace) {
        File('${workspace.directory.path}/note').writeAsStringSync('theirs\n');
      }) as Landed;
      final standing = one.tip;
      expect(standing, isNot(equals(landed.action.commit)));

      final result = await one.fetch(repositoryOf(there.path, mine.name));

      expect(result, isA<Landed>());
      expect((result as Landed).action.commit, equals(landed.action.commit));
      expect(one.tip, equals(landed.action.commit),
          reason: 'the local ref moved — this is the half push does over there');
      expect(utf8.decode(one.read('note')), equals('theirs\n'),
          reason: 'and the content arrived with it');
    });

    test('a fetch of an instance born elsewhere brings it into being here', () async {
      // The other direction of the same choice: no local ref at all. Nothing to
      // fast-forward, and the honest outcome is still a landing — this is how an
      // instance authored at another site first appears at this one.
      final born = await theirs().instance('two').create().act('note', (w) {
        File('${w.directory.path}/note').writeAsStringSync('elsewhere\n');
      }) as Landed;
      final newcomer = mine.instance('two');
      expect(newcomer.tip, isNull, reason: 'this site never heard of it');

      final result = await newcomer.fetch(repositoryOf(there.path, mine.name));

      expect(result, isA<Landed>());
      expect(newcomer.tip, equals(born.action.commit));
      expect([for (final i in mine.instances) i.id], contains('two'));
    });

    test('two lines that diverged say so, and nothing moves', () async {
      // Both sites act on the same instance from the same parent. Neither line
      // contains the other, so there is no line to extend — and joining them is
      // an act of its own, which fetch declines to invent.
      final ours = await one.act('note', (w) {
        File('${w.directory.path}/note').writeAsStringSync('ours\n');
      }) as Landed;
      await theirs().instance('one').act('note', (w) {
        File('${w.directory.path}/note').writeAsStringSync('theirs\n');
      });

      final theirTip = theirs().instance('one').tip;
      final result = await one.fetch(repositoryOf(there.path, mine.name));

      // **Diverged, and deliberately not `Contested`.** The fetch did not fail
      // — the substrate did what it was asked and the histories disagree. A
      // contest ends by re-reading the tip and retrying; this one re-reads the
      // tip and diverges identically, forever, because what ends it is someone
      // joining the lines.
      expect(result, isA<Diverged>());
      expect(result, isNot(isA<Contested>()));
      expect((result as Diverged).local, equals(ours.action.commit));
      expect(result.remote, equals(theirTip));
      expect(one.tip, equals(ours.action.commit),
          reason: 'our line is untouched — divergence is legitimate');
      expect(utf8.decode(one.read('note')), equals('ours\n'));
    });

    test('a remote that carries no such instance is not found, and not a '
        'refusal at all', () async {
      // **Not an `ActionResult`.** Nothing was refused: no gate was asked and
      // no ref moved under anyone. The caller named something that is not
      // there, which is the not-found answer — so it travels as an exception
      // and never as a value in the sealed type.
      final absent = mine.instance('never-born');
      final remote = repositoryOf(there.path, mine.name);

      await expectLater(
        absent.fetch(remote),
        throwsA(isA<InstanceNotAtRemote>()
            .having((e) => e.remote, 'remote', remote)
            .having((e) => e.instance, 'instance', 'never-born')),
      );
      expect(absent.tip, isNull);
    });
  });

  group('install of a repository this system never authored', () {
    // Real git, a real clone, and a source with no genesis branch — the
    // disjoint witness against the actual substrate, not the fake standing in
    // for it. Every install elsewhere in this file clones something born of
    // Entity.create, which already carries the ref install has to invent here.
    test('establishes genesis from the clone\'s own root, and the manifest '
        'names it', () async {
      const git = ProcessGit();
      final origin = _place('entity_foreign_origin_');
      final there = _place('entity_foreign_there_');
      addTearDown(() {
        for (final dir in [origin, there]) {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        }
      });
      final source = foreignRepository(
        git,
        origin.path,
        dirName: 't.foreign',
        declaredName: 't.imported',
      );

      final installed = await Entity.install(source, at: there.path);

      expect(installed.name, 't.imported',
          reason: 'the manifest, read off a clone that never had a genesis '
              'ref until install made one');
      expect(installed.genesis.sha, isNotEmpty);
      expect(installed.manifest.type, 'bentos.mem');
    });
  });

  group('release deletes disk, so possession is the whole question', () {
    // The one family where a wrong answer costs a directory instead of an error
    // message, and the only substrate that can be asked: the fake models
    // possession honestly, so every green above this line is a green about the
    // model. What the machine did was different — `git worktree remove` refused,
    // the refusal was read and discarded, and the directory was deleted by hand
    // afterwards. Both witnesses here are ordinary directories **made by the
    // shell**, never a tree minted by the code under judgment: a fixture cut by
    // the primitive is already a tenancy, which is the one case that cannot fail.

    /// A repository with committed content, stood up by Git itself.
    (String root, String plain) byHand(String label) {
      final root = Directory(
          Directory.systemTemp.createTempSync(label).resolveSymbolicLinksSync());
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final plain = Directory('${root.path}/plain')..createSync(recursive: true);
      File('${plain.path}/precious.txt').writeAsStringSync('mine\n');
      File('${root.path}/README.md').writeAsStringSync('top\n');
      for (final args in [
        ['init', '-q', root.path],
        ['-C', root.path, 'add', '-A'],
        ['-C', root.path, '-c', 'user.email=a@b', '-c', 'user.name=a',
          'commit', '-qm', 'one'],
      ]) {
        final r = Process.runSync('git', args);
        expect(r.exitCode, 0, reason: 'staging the witness: ${r.stderr}');
      }
      return (root.path, plain.path);
    }

    Future<({String err, int code})> release(String path, {String? from}) async {
      final err = StringBuffer();
      final runner = EntityRunner(
        out: StringBuffer(),
        err: err,
        currentDirectory: from ?? path,
      );
      await runner.run(['release', path]);
      return (err: err.toString(), code: runner.exitCode);
    }

    test('a directory that is no worktree of ours survives, and the refusal is '
        'loud', () async {
      final (root, plain) = byHand('entity_bystander_');

      final refused = await release(plain, from: root);

      expect(File('$plain/precious.txt').readAsStringSync(), 'mine\n',
          reason: 'the bystander is the assertion; everything else is how we '
              'learn that it held');
      expect(refused.code, EntityRunner.barredCode,
          reason: 'a silent zero over an untouched directory is the half of the '
              'defect that survives fixing the deletion');
      expect(refused.err, contains('barred'),
          reason: 'the word the code 3 now carries everywhere it is printed');

      // The same claim about the repository's own working tree — the directory a
      // wrong path names most often, and the one the incident actually cost.
      final onItself = await release(root);
      expect(onItself.code, EntityRunner.barredCode);
      expect(File('$root/README.md').existsSync(), isTrue);
      expect(Directory('$root/.git').existsSync(), isTrue);
    });

    test('a materialization of ours is still discarded', () async {
      final site = _place('entity_release_ours_');
      addTearDown(() {
        if (site.existsSync()) site.deleteSync(recursive: true);
      });
      final thing = Entity('t.thing', from: site.path).create();
      final one = thing.instance('one').create();
      final where = '${site.path}/face';
      thing.materialize(one.tip!, path: where);
      expect(Directory(where).existsSync(), isTrue);

      final released = await release(where, from: site.path);

      expect(released.code, 0, reason: released.err);
      expect(Directory(where).existsSync(), isFalse);
      // Deregistered and not merely deleted — the leak the verb exists to close.
      final register = Process.runSync('git', [
        '--git-dir=${repositoryOf(site.path, 't.thing')}',
        'worktree', 'list', '--porcelain',
      ]);
      expect('${register.stdout}', isNot(contains(where)));
    });
  });
}
