import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The instance family of the coreutil: the objects of a class, born from a
/// commit, and the acts legible on each.
void main() {
  late Site site;
  late Cli cli;

  setUp(() async {
    site = Site('cli');
    cli = Cli(site);
    await cli.run(['create', 't.chat', ...Cli.signed]);
  });
  tearDown(() => site.dispose());

  /// Takes an act through the API — the setup a log verb needs, driven one
  /// floor below the surface under test.
  Future<Action> act(String instance, String name, Map<String, String> files,
      {String actor = 'alfred'}) async {
    final result = await site.runAsync(() async {
      return Entity('t.chat', from: site.root.path).instance(instance).act(
            name,
            (workspace) {
              for (final entry in files.entries) {
                File('${workspace.directory.path}/${entry.key}')
                  ..parent.createSync(recursive: true)
                  ..writeAsStringSync(entry.value);
              }
            },
            actor: Actor(actor, email: '@test.local'),
          );
    });
    return (result as Landed).action;
  }

  group('entity new', () {
    test('births from genesis and prints the tip it stands at', () async {
      final genesis = (await cli.run(['info', 't.chat'])).out;

      final r = await cli.run(['new', 't.chat', 'c1']);
      expect(r.code, 0);
      expect(genesis, contains(r.out.trim()));
    });

    test('the instance then answers to ls, and genesis does not', () async {
      await cli.run(['new', 't.chat', 'c1']);
      await cli.run(['new', 't.chat', 'c2']);

      final r = await cli.run(['ls', 't.chat']);
      expect(r.code, 0);
      final ids = r.out.trim().split('\n').map((l) => l.split('\t').first);
      expect(ids, containsAll(['c1', 'c2']));
      expect(ids, isNot(contains('genesis')));
    });

    test('--from a live commit is a fork, and it inherits the past', () async {
      await cli.run(['new', 't.chat', 'c1']);
      final first = await act('c1', 'prompt', {'1.txt': 'hello'});

      final forked = await cli.run(['new', 't.chat', 'c2', '--from', first.commit.sha]);
      expect(forked.code, 0);
      expect(forked.out.trim(), first.commit.sha);

      final log = await cli.run(['log', 't.chat:c2']);
      expect(log.out, contains(first.commit.sha));
    });

    test('of an entity nobody installed here, not found', () async {
      final r = await cli.run(['new', 't.absent', 'c1']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.out, isEmpty);
    });

    test('of a name already born is barred, and never a not-found', () async {
      await cli.run(['new', 't.chat', 'c1']);

      final r = await cli.run(['new', 't.chat', 'c1']);

      // **Barred, not contested and not not-found.** Contested promises a
      // script that re-reads the tip and tries again will terminate, and here
      // it never will: the name is taken. Not-found is what this answered
      // before the birth became a compare-and-swap, when git's own
      // `cannot lock ref` arrived as a ProcessException and was graded by the
      // catch-all — the substrate's words, for a condition the caller has no
      // way to act on.
      expect(r.code, EntityRunner.barredCode);
      expect(r.err, contains('t.chat:c1 already exists'));
      expect(r.err, isNot(contains('cannot lock ref')));
      expect(r.out, isEmpty, reason: 'nothing was born, so nothing is printed');
    });

    test('with no instance named, it is a usage fault', () async {
      final r = await cli.run(['new', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<instance>'));
    });
  });

  group('entity ls', () {
    test('a class with no objects is silence, not a failure', () async {
      final r = await cli.run(['ls', 't.chat']);

      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('a coordinate lists the instance\'s tree, one level, names only',
        () async {
      await cli.run(['new', 't.chat', 'c1']);
      await act('c1', 'prompt', {
        'messages/1.json': 'a',
        'messages/2.json': 'b',
        'messages/deep/3.json': 'c',
      });

      final r = await cli.run(['ls', 't.chat:c1:messages']);
      expect(r.code, 0);
      expect(r.out.trim().split('\n'),
          ['messages/1.json', 'messages/2.json', 'messages/deep']);
    });

    test('a coordinate with no path lists the instance\'s root', () async {
      await cli.run(['new', 't.chat', 'c1']);
      await act('c1', 'prompt', {'messages/1.json': 'a', 'head': 'x'});

      final r = await cli.run(['ls', 't.chat:c1']);
      expect(r.code, 0);
      expect(r.out.trim().split('\n'), ['head', 'messages']);
    });

    test('--as-of lists the tree as it stood, not as it stands', () async {
      await cli.run(['new', 't.chat', 'c1']);
      final first = await act('c1', 'prompt', {'messages/1.json': 'a'});
      await act('c1', 'reply', {'messages/2.json': 'b'});

      final now = await cli.run(['ls', 't.chat:c1:messages']);
      expect(now.out.trim().split('\n'), hasLength(2));

      final then = await cli.run(
        ['ls', 't.chat:c1:messages', '--as-of', first.commit.sha],
      );
      expect(then.code, 0);
      expect(then.out.trim().split('\n'), ['messages/1.json']);
    });

    test('a path with nothing under it is silence, not a failure', () async {
      await cli.run(['new', 't.chat', 'c1']);
      // The instance holds something, elsewhere: an empty answer must come from
      // the path being empty, and not from the object being.
      await act('c1', 'prompt', {'messages/1.json': 'a'});

      final r = await cli.run(['ls', 't.chat:c1:nowhere']);
      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('an instance that was never born is not found', () async {
      final r = await cli.run(['ls', 't.chat:ghost']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('not born'));
    });
  });

  group('entity log', () {
    test('the acts, newest first, with what each one is', () async {
      await cli.run(['new', 't.chat', 'c1']);
      final first = await act('c1', 'prompt', {'1.txt': 'hello'});
      final second = await act('c1', 'reply', {'2.txt': 'hi'}, actor: 'llm');

      final r = await cli.run(['log', 't.chat:c1']);
      expect(r.code, 0);
      final lines = r.out.trim().split('\n');
      expect(lines, hasLength(2));
      expect(lines.first.split('\t'), [
        second.commit.sha,
        'reply',
        'llm',
        anything,
        // The sentence, empty when the act said nothing. Last, so every column
        // before it stays where a `cut` already found it.
        '',
      ]);
      expect(lines.last.split('\t')[0], first.commit.sha);
      expect(lines.last.split('\t')[1], 'prompt');
    });

    test('the birth is not an act — a fresh instance has an empty log',
        () async {
      await cli.run(['new', 't.chat', 'c1']);

      final r = await cli.run(['log', 't.chat:c1']);
      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('an instance that was never born is not found', () async {
      final r = await cli.run(['log', 't.chat:ghost']);

      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('a coordinate without an instance is a usage fault', () async {
      final r = await cli.run(['log', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<entity>:<instance>'));
    });
  });

  group('entity show', () {
    test('what one act changed, derived from the two states', () async {
      await cli.run(['new', 't.chat', 'c1']);
      await act('c1', 'prompt', {'1.txt': 'hello'});
      final second = await act('c1', 'reply', {'2.txt': 'hi'}, actor: 'llm');

      final r = await cli.run(['show', 't.chat:c1', second.commit.sha]);
      expect(r.code, 0);
      expect(r.out, contains('action\treply'));
      expect(r.out, contains('actor\tllm'));
      expect(r.out, contains('parent\t${second.parent.sha}'));
      expect(r.out, contains('added\t2.txt'));
      expect(r.out, isNot(contains('1.txt')));
    });

    test('an act this instance never took is not found', () async {
      await cli.run(['new', 't.chat', 'c1']);

      final r = await cli.run(['show', 't.chat:c1', 'deadbeef']);
      expect(r.code, EntityRunner.notFoundCode);
      expect(r.err, contains('deadbeef'));
    });
  });
}
