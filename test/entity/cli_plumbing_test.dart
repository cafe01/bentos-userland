import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The plumbing family of the coreutil — `resolve`, `tip`, `path`, `emit` and
/// `release`, the escape hatches and the hook's own callee.
///
/// **`work` and `commit` are gone**, and with them the tests that exercised
/// the private-area compare-and-swap: `act` commits in the instance's own
/// attached worktree now, and there is no swap left to contest. They asserted
/// a law that no longer exists, so they die with the seam rather than get
/// patched — including the poisoned-ambient-actor coverage `--actor-email,
/// against real Git` carried through `work`/`commit` alone. That coverage is
/// not replaced here and is owed against `entity act`.
void main() {
  late Site site;
  late Cli cli;

  setUp(() async {
    site = Site('cli');
    cli = Cli(site);
    await cli.run(['create', 't.chat', ...Cli.signed]);
    await cli.run(['new', 't.chat', 'c1']);
  });
  tearDown(() => site.dispose());

  group('entity tip and resolve', () {
    test('tip is the value an actor last landed on', () async {
      final tip = await cli.run(['tip', 't.chat:c1']);

      expect(tip.code, 0);
      expect(tip.out.trim(), hasLength(40));
    });

    test('an instance that was never born has no tip', () async {
      final r = await cli.run(['tip', 't.chat:ghost']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.out, isEmpty);
    });

    test('resolve turns the selection into where it actually stands', () async {
      // Standing it up straight at the port, exactly as [Instance.materialize]
      // will once it attaches too — resolve's own contract is *read
      // standingAt*, and that holds regardless of what materialize does today.
      final gitDir = repositoryOf(site.root.path, 't.chat');
      final tip = (await cli.run(['tip', 't.chat:c1'])).out.trim();
      final where = p.join(site.root.path, 'looker');
      site.git.worktreeAdd(gitDir, path: where, at: Commit(tip), branch: 'c1');

      final r = await cli.run(['resolve', 't.chat:c1']);

      expect(r.code, 0);
      expect(r.out.trim(), where);
    });

    test('an instance nobody materialized stands nowhere to resolve', () async {
      final r = await cli.run(['resolve', 't.chat:c1']);

      expect(r.code, EntityRunner.notFoundCode);
      expect(r.out, isEmpty);
    });
  });

  group('entity path', () {
    test('is the escape hatch, and it names a real repository', () async {
      final r = await cli.run(['path', 't.chat']);

      expect(r.code, 0);
      expect(r.out.trim(), repositoryOf(site.root.path, 't.chat'));
    });

    test('of an entity nobody installed here, not found', () async {
      final r = await cli.run(['path', 't.absent']);

      expect(r.code, EntityRunner.notFoundCode);
    });
  });

  group('entity release', () {
    test('is idempotent, and a path nobody opened is not a fault', () async {
      final where = '${site.root.path}/face';
      await cli.run(['materialize', 't.chat:c1', '--at', where]);

      expect((await cli.run(['release', where])).code, 0);
      expect((await cli.run(['release', where])).code, 0);
      expect((await cli.run(['release', '${site.root.path}/nowhere'])).code, 0);
    });

    test('deregisters a materialization', () async {
      final where = '${site.root.path}/face';
      await cli.run(['materialize', 't.chat:c1', '--at', where]);

      expect((await cli.run(['release', where])).code, 0);
      expect(Directory(where).existsSync(), isFalse);
    });
  });

  group('entity emit — the plumbing that calls into it', () {
    // Behaviour — a real transaction driving a real dispatch call — is proven
    // against the substrate in `subscribing_contract_test.dart`. What belongs
    // here is vocabulary: the arity and the phase word, both readable off the
    // argument list alone.

    test('without a phase, it is a usage fault', () async {
      final r = await cli.run(['emit', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name> <phase>'));
    });

    test('a phase that is not Git\'s own word is a usage fault', () async {
      final r = await cli.run(['emit', 't.chat', 'sideways']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('prepared, committed or aborted'));
    });
  });
}
