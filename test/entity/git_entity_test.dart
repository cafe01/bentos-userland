// The floor, against the real floor: a repository as an entity — state at a
// ref, the story as a log, the compare-and-swap on the ref, and the hook that
// consults the subscription table.

import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const ref = 'refs/heads/main';

late Directory tmp;

Future<GitEntity> newEntity([String name = 'thing']) =>
    GitEntity.init(Directory(p.join(tmp.path, name)));

/// Waits until [check] holds — the real floor is asynchronous, so a woken body
/// lands when it lands.
Future<void> until(
  Future<bool> Function() check, {
  Duration timeout = const Duration(seconds: 20),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('timed out waiting for $reason');
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('bentos-entity-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the state is the tree at a ref, and the story is the log', () async {
    final e = await newEntity();
    final first = await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open · the thing begins',
      tree: {'title': 'a thing', 'parts/one.json': '{"a":1}'},
    );
    await e.commit(
      ref: ref,
      expectedParent: first.id,
      author: 'model',
      message: 'say · a part added',
      tree: {'title': 'a thing', 'parts/one.json': '{"a":1}', 'parts/two.json': '{"b":2}'},
    );

    expect(await e.tree(ref), {
      'title': 'a thing',
      'parts/one.json': '{"a":1}',
      'parts/two.json': '{"b":2}',
    });

    final log = await e.log(ref);
    expect(log.map((t) => t.kind).toList(), ['open', 'say']);
    expect(log.map((t) => t.author).toList(), ['cafe', 'model']);
    expect(log.first.parent, isNull);
    expect(log.last.parent, log.first.id);

    // The worktree is materialized: the entity is legible on disk, and git
    // itself says the checkout matches the tip.
    expect(File(p.join(e.path, 'parts', 'two.json')).readAsStringSync(), '{"b":2}');
    final status = Process.runSync('git', ['-C', e.path, 'status', '--short']);
    expect(status.stdout, isEmpty, reason: 'the worktree is the state, not a copy');
  });

  test('a transaction diff is its payload', () async {
    final e = await newEntity();
    final opened = await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open',
      tree: {'title': 't', 'parts/one': '1'},
    );
    final added = await e.commit(
      ref: ref,
      expectedParent: opened.id,
      author: 'cafe',
      message: 'add',
      tree: {'title': 't', 'parts/one': '1', 'parts/two': '2'},
    );
    final reshaped = await e.commit(
      ref: ref,
      expectedParent: added.id,
      author: 'cafe',
      message: 'reshape',
      tree: {'title': 'T', 'parts/two': '2'},
    );

    expect((await e.diff(opened.id)).added, {'title', 'parts/one'});
    expect((await e.diff(added.id)).added, {'parts/two'});
    expect((await e.diff(added.id)).changed, isEmpty);
    final last = await e.diff(reshaped.id);
    expect(last.changed, {'title'});
    expect(last.removed, {'parts/one'});
  });

  test('the ref update is a compare-and-swap', () async {
    final e = await newEntity();
    final first = await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open',
      tree: {'title': 't'},
    );
    // Two bodies raised for one occurrence, each writing from the same tip.
    await e.commit(
      ref: ref,
      expectedParent: first.id,
      author: 'a',
      message: 'reply · first',
      tree: {'title': 't', 'a': 'a'},
    );
    expect(
      () => e.commit(
        ref: ref,
        expectedParent: first.id,
        author: 'b',
        message: 'reply · second',
        tree: {'title': 't', 'b': 'b'},
      ),
      throwsA(isA<RefRaceLost>()),
    );
    expect((await e.log(ref)).length, 2);

    // And the ref must not exist when no parent is expected.
    expect(
      () => e.commit(
        ref: ref,
        expectedParent: null,
        author: 'c',
        message: 'open · again',
        tree: {'title': 't'},
      ),
      throwsA(isA<RefRaceLost>()),
    );
  });

  test('a branch is a second ref over the same history', () async {
    final e = await newEntity();
    final first = await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open',
      tree: {'title': 't'},
    );
    await e.commit(
      ref: ref,
      expectedParent: first.id,
      author: 'cafe',
      message: 'say',
      tree: {'title': 't', 'x': 'x'},
    );

    await e.branch(ref: 'refs/heads/fork-a', at: first.id);
    await e.commit(
      ref: 'refs/heads/fork-a',
      expectedParent: first.id,
      author: 'cafe',
      message: 'say · elsewhere',
      tree: {'title': 't', 'y': 'y'},
    );

    expect((await e.log(ref)).map((t) => t.message).toList(), ['open', 'say']);
    expect((await e.log('refs/heads/fork-a')).map((t) => t.message).toList(),
        ['open', 'say · elsewhere']);
    expect(await e.tree('refs/heads/fork-a'), {'title': 't', 'y': 'y'});
    // The unchecked-out branch folds exactly like the checked-out one, and the
    // parent's worktree never moved.
    expect(File(p.join(e.path, 'x')).existsSync(), isTrue);
    expect(File(p.join(e.path, 'y')).existsSync(), isFalse);
  });

  test('the hook fires on the transaction and wakes the table', () async {
    final e = await newEntity();
    final witness = p.join(tmp.path, 'woken');
    Arming(e).subscribe('echo "\$BENTOS_REF \$BENTOS_NEW" >> $witness');

    final first = await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open',
      tree: {'title': 't'},
    );
    await until(() async => File(witness).existsSync(), reason: 'the first wake');
    await e.commit(
      ref: ref,
      expectedParent: first.id,
      author: 'cafe',
      message: 'say',
      tree: {'title': 't', 'x': 'x'},
    );
    await until(
      () async => File(witness).readAsLinesSync().length == 2,
      reason: 'the second wake',
    );

    final woken = File(witness).readAsLinesSync();
    expect(woken.first, '$ref ${first.id}');
    expect(woken.last, endsWith((await e.head(ref))!));
  });

  test('the hook finds a coreutil the caller had no PATH for', () async {
    // A desktop-launched process inherits launchd's minimal PATH, so a table
    // entry naming `llm` by its bare name was found by every shell and by
    // nothing the person double-clicked. The hook is driven here with exactly
    // that PATH, and the body it must reach lives only in the install prefix.
    final e = await newEntity();
    final home = Directory(p.join(tmp.path, 'home'))..createSync();
    final bin = Directory(p.join(home.path, '.local', 'bin'))..createSync(recursive: true);
    final witness = p.join(tmp.path, 'woken');
    final body = File(p.join(bin.path, 'a-coreutil'))
      ..writeAsStringSync('#!/bin/sh\necho "\$@" >> $witness\n');
    Process.runSync('chmod', ['+x', body.path]);

    Arming(e).subscribe('a-coreutil "\$BENTOS_REF"');
    final hook = p.join(e.gitDir.path, 'hooks', 'reference-transaction');

    final run = await Process.start(
      '/bin/sh',
      [hook, 'committed'],
      workingDirectory: e.path,
      environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
      includeParentEnvironment: false,
    );
    run.stdin.writeln('0000000 1111111 $ref');
    await run.stdin.close();
    await run.exitCode;

    await until(() async => File(witness).existsSync(), reason: 'the coreutil to be found');
    expect(File(witness).readAsStringSync().trim(), ref);
  });

  test('a materialization is not an occurrence', () async {
    final e = await newEntity();
    final witness = p.join(tmp.path, 'woken');
    Arming(e).subscribe('echo x >> $witness');
    await e.commit(
      ref: ref,
      expectedParent: null,
      author: 'cafe',
      message: 'open',
      tree: {'title': 't'},
    );
    await until(() async => File(witness).existsSync(), reason: 'the wake');

    // The porcelain way of syncing a worktree rewrites the ref to its own
    // value. Nobody may be woken by that, or every entity is a motor — which is
    // also why the commit path materializes with `read-tree` instead, a
    // plumbing that touches no ref at all.
    Process.runSync('git', ['-C', e.path, 'reset', '--hard', '-q']);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(witness).readAsLinesSync().length, 1);
  });
}
