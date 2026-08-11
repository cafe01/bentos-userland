import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// Dispatch is infrastructure of one installation, like the tables and the
// journal beside it. It is not on the public surface, so it is proven where it
// lives.
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:bentos_userland/src/entity/deliverer.dart';
import 'package:bentos_userland/src/entity/journal.dart';
// The concrete port is not part of the public surface — a caller never names it,
// because the ambient already is it. This suite must, for the same reason
// `construction_test` must: dispatch reads real commit objects out of a real
// object store, and a fake one would be a suite proving the double.
import 'package:bentos_userland/src/git/process_git.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// **Dispatch** — what the primitive does with a published occurrence: match it
/// against the arming tables, wake what matched, and write down what happened.
///
/// Everything here runs against the real substrate and real bodies, and that is
/// not a preference. Dispatch's whole subject matter is the seam between three
/// processes — Git, the primitive, the woken body — and a double at any of the
/// three would be testimony about a transaction that never happened.
///
/// The in-process groups drive [Entity.emit] with the triples Git would hand
/// it, which is the shim's entire contract. That Git actually hands them over,
/// and actually obeys the exit code, is the one claim no Dart assertion
/// reaches — it is proven at the bottom of this file, through a real hook.
void main() {
  const git = ProcessGit();

  late Directory site;
  late Entity entity;
  late String gitDir;

  setUp(() {
    site = _place('entity_dispatch');
    entity = Entity('bentos.llm', from: site.path).create();
    gitDir = repositoryOf(site.path, entity.name);
    // **The installed shim is removed, and every test below depends on it.**
    // `create` arms the installation with the shipped publisher, so a ref moved
    // here would dispatch twice: once through the hook and once through the
    // explicit `emit` these tests make. Removing it leaves exactly one
    // publisher in the room, which is what lets an assertion name who acted.
    // The hook's own behaviour is not this file's subject until the last group,
    // which installs a fixture of its own.
    File(p.join(gitDir, ArmingTables.hookPath)).deleteSync();
  });

  /// **A deliverer outlives the test that woke it, and that is the design.** It
  /// is detached from `emit` on purpose, so it may still be appending its line
  /// when a test that never asserted one has already ended — and a recursive
  /// delete racing a file being created answers *Directory not empty*. The
  /// deletion is retried rather than the detachment weakened; what is being
  /// cleaned up is a temporary directory, so giving up quietly at the end costs
  /// nothing and asserts nothing either way.
  tearDown(() async {
    for (var attempt = 0; site.existsSync() && attempt < 40; attempt++) {
      try {
        site.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  /// A commit object over [files] parented at [parent], written into the
  /// entity's own store and **not landed**. The swap is what a caller is about
  /// to perform, or what Git is about to be told about.
  Commit commit(
    Map<String, String> files, {
    required Commit parent,
    String noun = 'prompt',
    String? say,
    String actor = 'alfred',
  }) {
    final work = Directory('${site.path}/stage');
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    for (final entry in files.entries) {
      File('${work.path}/${entry.key}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    return Commit(git.commitTree(
      gitDir,
      tree: git.writeTree(gitDir, workTree: work.path),
      parents: [parent.sha],
      message: Action.messageFor(noun, say: say),
      actor: Actor(actor),
    ));
  }

  /// An instance born from genesis, and the tip it stands at.
  Commit born(String id) {
    git.branch(gitDir, name: id, startPoint: entity.genesis);
    return entity.genesis;
  }

  /// The triple Git would put on the shim's stdin for a move of [id]'s ref.
  TransactionRefUpdate moving(String id, {required Commit from, required Commit to}) =>
      TransactionRefUpdate(old: from, commit: to, ref: 'refs/heads/$id');

  /// Every journal line, raw — the wire, not the types that read it. Asserted
  /// this way wherever the claim is about what was written down, because a
  /// round trip through the reader would prove the pair agree and not that the
  /// field is there.
  List<Map<String, Object?>> lines() {
    final file = File(p.join(gitDir, ArmingTables.tablesDirName, Journal.fileName));
    if (!file.existsSync()) return const [];
    return [
      for (final line in file.readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];
  }

  List<Map<String, Object?>> occurrences() =>
      [for (final l in lines()) if (l['kind'] == 'occurrence') l];

  List<Map<String, Object?>> deliveries() =>
      [for (final l in lines()) if (l['kind'] == 'delivery') l];

  // ------------------------------------------------------------------------
  group('what is not an occurrence', () {
    // Five conditions, and the two the old publisher knew about are the ones a
    // rewrite drops: a ref outside `refs/heads/*` and a move that moves
    // nothing. A `fetch` carries `refs/remotes/*` in the same transaction, so
    // without the first, an ordinary fetch mints an occurrence on an instance
    // named `remotes/origin/main` — an object that does not exist, journaled
    // forever, and matched against by every subscriber armed on `*`.

    late File fired;

    setUp(() {
      fired = File('${site.path}/fired');
      entity.on(
        {EventPattern.parse('*.landed'), EventPattern.parse('*.attempted')},
        command: [_body(site, 'touch', 'echo "\$@" > "${fired.path}"')],
      );
    });

    /// Nothing was published: no line written, and nothing woken. Both halves,
    /// because a skip that journals nothing but still wakes a body has only
    /// moved the fiction one floor down.
    Future<void> silent(TransactionRefUpdate update) async {
      expect(await entity.emit(EventPhase.landed, [update]), equals(0));
      expect(occurrences(), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fired.existsSync(), isFalse);
    }

    test('a birth is not an act upon an object', () async {
      final tip = born('demo');
      await silent(TransactionRefUpdate(
          old: Commit.zero, commit: tip, ref: 'refs/heads/demo'));
    });

    test('a deletion is not one either', () async {
      final tip = born('demo');
      await silent(TransactionRefUpdate(
          old: tip, commit: Commit.zero, ref: 'refs/heads/demo'));
    });

    test('genesis is the structure instances are born from, not one of them',
        () async {
      final next = commit({'entity.yaml': 'name: bentos.llm\n'},
          parent: entity.genesis);
      await silent(TransactionRefUpdate(
          old: entity.genesis, commit: next, ref: Entity.genesisRef));
    });

    test('a ref outside refs/heads is not an instance', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      // What a fetch moves. An occurrence here would name the instance
      // `remotes/origin/demo`.
      await silent(TransactionRefUpdate(
          old: tip, commit: next, ref: 'refs/remotes/origin/demo'));
      await silent(
          TransactionRefUpdate(old: tip, commit: next, ref: 'refs/tags/v1'));
      await silent(
          TransactionRefUpdate(old: tip, commit: next, ref: 'refs/stash'));
    });

    test('a ref that does not move published nothing', () async {
      final tip = born('demo');
      await silent(moving('demo', from: tip, to: tip));
    });

    test('a real move on a real instance is published — the falsifier', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      expect(await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]),
          equals(0));
      expect(occurrences(), hasLength(1),
          reason: 'the five skips above must be skipping, not the whole verb '
              'declining to journal anything at all');
    });
  });

  // ------------------------------------------------------------------------
  group('the occurrence line', () {
    test('carries the act, read off the commit the ref moved to', () async {
      final tip = born('demo');
      final next = commit({'turn': 'hello'},
          parent: tip, noun: 'prompt', say: 'ask about the weather', actor: 'cafe');

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      final line = occurrences().single;
      expect(line['entity'], equals('bentos.llm'));
      expect(line['instance'], equals('demo'));
      expect(line['noun'], equals('prompt'),
          reason: 'the noun is the Bentos-Action trailer, never the ref');
      expect(line['phase'], equals('landed'));
      expect(line['commit'], equals(next.sha));
      expect(line['parent'], equals(tip.sha),
          reason: 'the value the ref held before it — what an attempted gate '
              'judges against');
      expect(line['actor'], equals('cafe'));
      expect(line['sentence'], equals('ask about the weather'));
      expect(DateTime.parse(line['instant']! as String), isNotNull);
    });

    test('a commit with no declared noun journals the sentinel, and * matches it',
        () async {
      final tip = born('demo');
      // A commit this system did not author — no trailer at all. The condition
      // the sentinel exists for, and the one a required field would otherwise
      // have no value to take.
      final work = Directory('${site.path}/bare')..createSync(recursive: true);
      File('${work.path}/a').writeAsStringSync('1');
      final next = Commit(git.commitTree(
        gitDir,
        tree: git.writeTree(gitDir, workTree: work.path),
        parents: [tip.sha],
        message: 'no trailer here\n',
        actor: const Actor('stranger'),
      ));

      final woken = File('${site.path}/woken');
      entity.on({EventPattern.parse('*.landed')},
          command: [_body(site, 'noun', 'echo "\$BENTOS_NOUN" > "${woken.path}"')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      expect(occurrences().single['noun'], equals('-'));
      await _settles(woken);
      expect(woken.readAsStringSync().trim(), equals('-'),
          reason: 'the sentinel is what * matched, so it must be what the body '
              'is handed');
    });

    test('one call handles every ref in the transaction', () async {
      final one = born('one');
      final two = born('two');
      final nextOne = commit({'a': '1'}, parent: one, noun: 'prompt');
      final nextTwo = commit({'a': '2'}, parent: two, noun: 'reply');

      await entity.emit(EventPhase.landed, [
        moving('one', from: one, to: nextOne),
        moving('two', from: two, to: nextTwo),
      ]);

      expect(
        [for (final l in occurrences()) '${l['instance']}/${l['noun']}'],
        equals(['one/prompt', 'two/reply']),
        reason: 'one process start per transaction, and argument order is the '
            'order they are journaled in',
      );
    });
  });

  // ------------------------------------------------------------------------
  group('journaled before the table is read', () {
    // The claim the whole two-kinds-of-line design rests on. An unarmed
    // installation proves the write is unconditional; only a body that reads
    // the journal and finds itself already in it proves the write came *first*.

    test('an installation with nothing armed still journals the occurrence',
        () async {
      expect(entity.listeners, isEmpty);
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      expect(occurrences(), hasLength(1),
          reason: 'a reader promised it needed nothing armed must see an '
              'unarmed entity');
    });

    test('a woken body finds its own occurrence already written', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final seen = File('${site.path}/seen');
      final journalPath =
          p.join(gitDir, ArmingTables.tablesDirName, Journal.fileName);

      entity.on(
        {EventPattern.parse('prompt.landed')},
        command: [
          _body(site, 'reads-journal',
              'grep -c "\$BENTOS_SHA" "$journalPath" > "${seen.path}"'),
        ],
      );

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      // Existence is not the artifact here — the redirection creates the file
      // before `grep` has written a byte into it, so waiting on the path alone
      // reads an empty string and parses nothing. The artifact is the count.
      await _settlesUntil(() =>
          seen.existsSync() && seen.readAsStringSync().trim().isNotEmpty);

      expect(int.parse(seen.readAsStringSync().trim()), greaterThanOrEqualTo(1),
          reason: 'the occurrence is journaled before the table is read, so '
              'the body it wakes can already see it');
    });

    test('a gate at attempted sees it too, before it refuses', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final seen = File('${site.path}/seen');
      final journalPath =
          p.join(gitDir, ArmingTables.tablesDirName, Journal.fileName);

      entity.on(
        {EventPattern.parse('prompt.attempted')},
        command: [
          _body(site, 'gate', '''
grep -c "\$BENTOS_SHA" "$journalPath" > "${seen.path}"
echo "'\$BENTOS_NOUN' is illegal here"
exit 1
'''),
        ],
      );

      final code =
          await entity.emit(EventPhase.attempted, [moving('demo', from: tip, to: next)]);

      expect(code, isNot(0));
      expect(seen.existsSync(), isTrue,
          reason: 'a held gate runs in line, so its artifact is on disk the '
              'moment emit returns');
      expect(int.parse(seen.readAsStringSync().trim()), greaterThanOrEqualTo(1),
          reason: 'a refusal does not unwrite the occurrence that was '
              'attempted');
      expect(occurrences().single['phase'], equals('attempted'));
    });
  });

  // ------------------------------------------------------------------------
  group('matching', () {
    test('the instance glob and the action glob must both match', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip, noun: 'prompt');

      final wrongInstance = File('${site.path}/wrong-instance');
      final wrongAction = File('${site.path}/wrong-action');
      final right = File('${site.path}/right');

      entity.on({EventPattern.parse('prompt.landed')},
          instance: 'other',
          command: [_body(site, 'wi', 'touch "${wrongInstance.path}"')]);
      entity.on({EventPattern.parse('reply.landed')},
          instance: 'demo',
          command: [_body(site, 'wa', 'touch "${wrongAction.path}"')]);
      entity.on({EventPattern.parse('prompt.landed')},
          instance: 'demo', command: [_body(site, 'r', 'touch "${right.path}"')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settles(right);

      expect(wrongInstance.existsSync(), isFalse);
      expect(wrongAction.existsSync(), isFalse);
    });

    test('a line armed on * receives the instance of this transaction', () async {
      // Every manifest-armed line is `*`, because at install time no instance
      // exists. The instance is a fact of the occurrence, not of the line.
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final where = File('${site.path}/where');
      entity.on({EventPattern.parse('*.landed')},
          instance: '*',
          command: [
            _body(site, 'where', 'echo "\$BENTOS_INSTANCE" > "${where.path}"')
          ]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settles(where);

      expect(where.readAsStringSync().trim(), equals('demo'));
    });

    test('a phase reads only its own table', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final attempted = File('${site.path}/attempted');
      entity.on({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'a', 'touch "${attempted.path}"')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(attempted.existsSync(), isFalse);
      expect(deliveries(), isEmpty,
          reason: 'a line that did not match leaves no delivery record');
    });
  });

  // ------------------------------------------------------------------------
  group('a once line is spent when it fires', () {
    test('and it is pruned before its command runs', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final table = File(p.join(gitDir, ArmingTables.tablesDirName, 'landed'));
      final saw = File('${site.path}/saw');

      final armed = entity.once({EventPattern.parse('prompt.landed')},
          command: [
            _body(site, 'once', 'cat "${table.path}" > "${saw.path}"'),
          ]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settles(saw);

      expect(saw.readAsStringSync(), isNot(contains(armed.id)),
          reason: 'fired means spent, and the pruning happens before the body '
              'runs so a refusal can never leave a line able to fire twice');
      expect(entity.listeners.where((r) => r.id == armed.id), isEmpty);
    });

    test('a once gate that refuses is spent all the same', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final armed = entity.once({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'no', 'exit 1')]);

      expect(
          await entity.emit(
              EventPhase.attempted, [moving('demo', from: tip, to: next)]),
          isNot(0));
      expect(entity.listeners.where((r) => r.id == armed.id), isEmpty,
          reason: 'the refusal leaves emit immediately; a line pruned after the '
              'command would survive its own firing');
    });
  });

  // ------------------------------------------------------------------------
  group('the two phases', () {
    test('attempted runs held, in table order', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final order = File('${site.path}/order');

      entity.on({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'first', 'echo first >> "${order.path}"')]);
      entity.on({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'second', 'echo second >> "${order.path}"')]);

      expect(
          await entity.emit(
              EventPhase.attempted, [moving('demo', from: tip, to: next)]),
          equals(0));

      expect(order.readAsLinesSync(), equals(['first', 'second']),
          reason: 'held means the work is done when emit returns — no settle '
              'anywhere in this test');
    });

    test('landed is detached: emit returns before the body finishes', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final slow = File('${site.path}/slow');
      entity.on({EventPattern.parse('prompt.landed')},
          command: [_body(site, 'slow', 'sleep 1; touch "${slow.path}"')]);

      final code =
          await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      expect(code, equals(0));
      expect(slow.existsSync(), isFalse,
          reason: 'the landing is never held hostage to what it wakes');
      await _settles(slow, within: const Duration(seconds: 10));
    });

    test('a detached body that fails cannot change the answer', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      entity.on({EventPattern.parse('prompt.landed')},
          command: [_body(site, 'fails', 'exit 3')]);

      expect(
          await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]),
          equals(0),
          reason: 'the ref has already moved; there is nothing left to refuse');
    });

    test('a refusal stops the transaction where it stopped', () async {
      // Two refs in one transaction, the first one gated. What is journaled is
      // a fact about when the transaction stopped, and the earlier occurrence
      // is not retroactively unwritten.
      final one = born('one');
      final two = born('two');
      final nextOne = commit({'a': '1'}, parent: one);
      final nextTwo = commit({'a': '2'}, parent: two);

      entity.on({EventPattern.parse('prompt.attempted')},
          instance: 'one', command: [_body(site, 'gate', 'exit 1')]);

      expect(
        await entity.emit(EventPhase.attempted, [
          moving('one', from: one, to: nextOne),
          moving('two', from: two, to: nextTwo),
        ]),
        isNot(0),
      );

      expect([for (final l in occurrences()) l['instance']], equals(['one']),
          reason: 'the first stands, the second never happened');
    });
  });

  // ------------------------------------------------------------------------
  group('the delivery line', () {
    // `reactor.log`'s replacement, and the whole content of *an armed body no
    // longer fails in silence*: the bytes addressed to the line that produced
    // them, with the exit code beside them.
    //
    // At `.attempted` the gate is held, so `emit` itself has the outcome. At
    // `.landed` and `.refused` it does not and must not — the line is written
    // by a **deliverer**, a process `emit` starts detached and does not wait
    // for, which starts the body ordinarily and does. That the deliverer stays
    // off the public surface is a constraint on its construction and not a
    // claim these asserts can reach: nothing below names it, which is the most
    // a suite can say about a thing only `emit` is allowed to produce.

    test('a held gate that refuses leaves its account behind', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final armed = entity.on({EventPattern.parse('prompt.attempted')},
          command: [
            _body(site, 'gate', "echo \"'\$BENTOS_NOUN' is illegal here\"; exit 7")
          ]);

      await entity.emit(EventPhase.attempted, [moving('demo', from: tip, to: next)]);

      final line = deliveries().single;
      expect(line['subscriber'], equals(armed.id));
      expect(line['exitCode'], equals(7),
          reason: "the body's own code, carried and never reinterpreted");
      expect(line['output'], contains("'prompt' is illegal here"));
      expect(line['command'], isA<List<Object?>>());
      expect(line['commit'], equals(next.sha));
    });

    test('a detached body that fails is a line with a non-zero code', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final armed = entity.on({EventPattern.parse('prompt.landed')},
          command: [_body(site, 'fails', 'echo "could not reach the model" >&2; exit 4')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settlesUntil(() => deliveries().isNotEmpty);

      final line = deliveries().single;
      expect(line['subscriber'], equals(armed.id));
      expect(line['exitCode'], equals(4));
      expect(line['output'], contains('could not reach the model'),
          reason: 'stdout and stderr both, captured whole — a failure with its '
              'account discarded is the silence this file exists to end');
    });

    test('a body that could not be executed at all is still a line', () async {
      // The deliverer journals unconditionally, including its own failures. A
      // deliverer that only records executions that happened reintroduces
      // silence at the one place this file is closing it — and *not found* is
      // the commonest way an armed line dies.
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final armed = entity.on({EventPattern.parse('prompt.landed')},
          command: ['${site.path}/no-such-body']);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settlesUntil(() => deliveries().isNotEmpty);

      final line = deliveries().single;
      expect(line['subscriber'], equals(armed.id));
      expect(line['exitCode'], isNot(0));
      expect(line['output'], isNot(isEmpty),
          reason: "whatever the substrate said, carried — a missing line would "
              'be the failure mode with the loudest cause and the quietest '
              'record');
    });

    test('the deliverer is what is detached, and the body is not', () async {
      // Inverting these two gets a detached body nobody can observe, which is
      // today's design with an extra process in it. The observable difference:
      // emit returns with no delivery line yet, and the line appears **with the
      // body's outcome in it** once the body is done — which is only possible
      // if something waited for the body after emit stopped waiting for it.
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      entity.on({EventPattern.parse('prompt.landed')},
          command: [_body(site, 'slow', 'sleep 1; echo late; exit 5')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);

      expect(deliveries(), isEmpty,
          reason: 'emit did not wait — the deliverer is detached from it');
      await _settlesUntil(() => deliveries().isNotEmpty,
          within: const Duration(seconds: 15));

      final line = deliveries().single;
      expect(line['exitCode'], equals(5));
      expect(line['output'], contains('late'),
          reason: 'the deliverer waited for the body, which is the half of the '
              'asymmetry that makes the outcome knowable at all');
    });

    test('an occurrence nobody matched leaves no delivery line', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(occurrences(), hasLength(1));
      expect(deliveries(), isEmpty);
    });

    test('two matching lines are two deliveries of one occurrence', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final a = entity.on({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'a', 'exit 0')]);
      final b = entity.on({EventPattern.parse('prompt.attempted')},
          command: [_body(site, 'b', 'exit 0')]);

      await entity.emit(EventPhase.attempted, [moving('demo', from: tip, to: next)]);

      expect([for (final l in deliveries()) l['subscriber']],
          equals([a.id, b.id]));
      expect(occurrences(), hasLength(1),
          reason: 'one occurrence, however many lines matched it');
    });
  });

  // ------------------------------------------------------------------------
  group('the context a woken body receives', () {
    /// The environment a body saw, as a map. Written by the body itself, which
    /// is the only witness that answers for what the process actually got.
    Future<Map<String, String>> environmentOf(EventPhase phase) async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip, noun: 'prompt');
      final dump = File('${site.path}/env');
      entity.on({EventPattern.parse('prompt.${phase.suffix}')},
          command: [
            _body(site, 'env',
                'env | grep -E "^(BENTOS_|GIT_)" | sort > "${dump.path}"')
          ]);

      await entity.emit(phase, [moving('demo', from: tip, to: next)]);
      // The redirection creates the file before `env | grep | sort` has
      // written a byte into it — the same race already fixed above for the
      // journal-reading body, missed here. `_settles` on existence alone
      // reads an empty file under contention.
      await _settlesUntil(() => dump.existsSync() && dump.readAsStringSync().trim().isNotEmpty);

      return {
        for (final line in dump.readAsLinesSync())
          line.substring(0, line.indexOf('=')):
              line.substring(line.indexOf('=') + 1),
      };
    }

    test('nine variables, in two registers', () async {
      final env = await environmentOf(EventPhase.landed);

      // The address — always laid, and its absence is the defect this replaces:
      // the shell publisher laid neither PLACE nor COORD, so every gate that
      // needed to know where it stood died where nothing could see it.
      expect(env['BENTOS_PLACE'], equals(site.path));
      expect(env['BENTOS_ENTITY'], equals('bentos.llm'));
      expect(env['BENTOS_INSTANCE'], equals('demo'));
      expect(env['BENTOS_COORD'], equals('bentos.llm:demo'));

      // The occurrence — laid because there is one.
      expect(env['BENTOS_EVENT'], equals('prompt.landed'));
      expect(env['BENTOS_PHASE'], equals('landed'));
      expect(env['BENTOS_NOUN'], equals('prompt'));
      expect(env['BENTOS_SHA'], isNotEmpty);
      expect(env['BENTOS_OLD'], isNotEmpty);
    });

    test('the parent rides, and it is the value the ref still holds at attempted',
        () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final dump = File('${site.path}/parent');
      entity.on({EventPattern.parse('prompt.attempted')},
          command: [
            _body(site, 'parent',
                'echo "\$BENTOS_OLD \$BENTOS_SHA" > "${dump.path}"')
          ]);

      await entity.emit(EventPhase.attempted, [moving('demo', from: tip, to: next)]);

      expect(dump.readAsStringSync().trim(), equals('${tip.sha} ${next.sha}'),
          reason: 'a gate judges the act where it stands, and where it stands '
              'is the parent — folding the tip would lean on transaction '
              'timing to be right');
    });

    test('the transaction environment is stripped from what it wakes', () async {
      // A body that inherited GIT_DIR or a quarantine would run its own git
      // against a store that is about to vanish. Five variables, and the last
      // is the one that only exists on a push.
      final env = await environmentOf(EventPhase.landed);
      for (final key in const [
        'GIT_DIR',
        'GIT_WORK_TREE',
        'GIT_INDEX_FILE',
        'GIT_OBJECT_DIRECTORY',
        'GIT_QUARANTINE_PATH',
      ]) {
        expect(env.containsKey(key), isFalse,
            reason: '$key must not survive into a woken body');
      }
    });

    test('the body is called with the occurrence on argv as well', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final argv = File('${site.path}/argv');
      entity.on({EventPattern.parse('prompt.landed')},
          command: [_body(site, 'argv', 'echo "\$@" > "${argv.path}"')]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settles(argv);

      expect(
        argv.readAsStringSync().trim(),
        equals('$gitDir refs/heads/demo ${tip.sha} ${next.sha} prompt'),
        reason: 'the argv contract the old publisher had, unchanged — a body '
            'armed before the trampoline keeps working after it',
      );
    });

    test('an argument the caller drew a boundary around keeps it', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final got = File('${site.path}/got');
      entity.on({EventPattern.parse('prompt.landed')},
          command: [
            _body(site, 'args', 'echo "\$1" > "${got.path}"'),
            'two words',
          ]);

      await entity.emit(EventPhase.landed, [moving('demo', from: tip, to: next)]);
      await _settles(got);

      expect(got.readAsStringSync().trim(), equals('two words'));
    });
  });

  // ------------------------------------------------------------------------
  group('the environment the trailer is read under', () {
    // **The guard the condemned shell knew and the contract nearly dropped.**
    // A pushed transaction's objects live under GIT_QUARANTINE_PATH until the
    // push is accepted, so the commit is only readable while that environment
    // is intact. Strip it too early and every pushed act journals a nounless
    // occurrence; strip it too late and the body it wakes holds a store about
    // to vanish. The asymmetry is not observable in this process — it needs a
    // real push, arriving at a real hook.

    test('an act arriving by push journals its noun, not the sentinel',
        () async {
      final downstream = _place('entity_dispatch_downstream');
      try {
        // The instance must already stand at both ends: a ref arriving for the
        // first time is a birth, and a birth is not an act. What has to cross
        // the wire is a *move*.
        final tip = born('demo');
        final first = commit({'a': '1'}, parent: tip, noun: 'note');
        expect(
          git
              .updateRef(gitDir,
                  ref: 'refs/heads/demo', newCommit: first, expected: tip)
              .moved,
          isTrue,
        );

        final mirror = await Entity.install(
          repositoryOf(site.path, entity.name),
          at: downstream.path,
          as: entity.name,
        );
        final mirrorDir = repositoryOf(downstream.path, mirror.name);
        _installFixtureHook(mirrorDir, downstream.path, mirror.name);

        final next = commit({'a': '2'}, parent: first, noun: 'prompt');
        expect(
          git
              .updateRef(gitDir,
                  ref: 'refs/heads/demo', newCommit: next, expected: first)
              .moved,
          isTrue,
        );

        await git.push(gitDir, remote: mirrorDir, ref: 'refs/heads/demo');

        final journalled = File(p.join(
            mirrorDir, ArmingTables.tablesDirName, Journal.fileName));
        expect(journalled.existsSync(), isTrue,
            reason: 'the receiving side runs its own hook — federation uses '
                'exactly the mechanism local action uses');
        final nouns = [
          for (final line in journalled.readAsLinesSync())
            if (line.trim().isNotEmpty)
              (jsonDecode(line) as Map<String, Object?>)['noun'],
        ];
        expect(nouns, contains('prompt'),
            reason: 'the trailer is read with the transaction environment '
                'intact; stripping the quarantine before the read leaves every '
                'pushed act nounless');
      } finally {
        if (downstream.existsSync()) downstream.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ------------------------------------------------------------------------
  group('which deliverer is started', () {
    // **This proves the branch and nothing beyond it.** Every test above runs
    // from source, so every deliverer they start is the source-mode one; the
    // compiled mode — the shipped executable re-exec'd on a hidden verb — is
    // reached by no assertion in this file, and that gap is real. What is
    // checkable cheaply is which command the branch composes, which is where a
    // silent inversion would sit.

    test('from source, the deliverer is this runtime running this library', () {
      expect(
        delivererCommandFrom(
            executable: '/usr/bin/dart', source: '/pkg/deliverer.dart', payload: '{}'),
        equals(['/usr/bin/dart', 'run', '/pkg/deliverer.dart', '{}']),
      );
    });

    test('compiled, it is this executable on the hidden verb', () {
      expect(
        delivererCommandFrom(
            executable: '/usr/local/bin/entity', source: null, payload: '{}'),
        equals(['/usr/local/bin/entity', delivererVerb, '{}']),
        reason: 'package resolution answers nothing in a compiled executable, '
            'and dispatch is reached through the shim, which execs `entity`',
      );
    });

    test('and this suite is running the source branch', () async {
      expect(await delivererSource(), isNotNull,
          reason: 'the mode every assertion in this file exercises — said out '
              'loud, so the untested branch is visible as untested');
    });
  });

  // ------------------------------------------------------------------------
  group('through a real transaction', () {
    // **The claim no Dart assertion reaches.** That a non-zero exit at
    // `prepared` aborts the update is a fact about Git, not about us, and
    // everything about `attempted` being a gate is false without it. What runs
    // here is a fixture publisher written for this file alone — never the
    // shipped shim, and never derived from it, so a later reader cannot mistake
    // one for the other.

    test('a gate that refuses aborts the update — the ref does not move',
        () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);

      entity.on({EventPattern.parse('prompt.attempted')},
          command: [
            _body(site, 'gate', "echo \"'\$BENTOS_NOUN' is illegal here\" >&2; exit 1")
          ]);
      // **After the arming, and it must be.** `Entity.on` reaches
      // `ArmingTables.ensureArmed`, which rewrites the shipped shim — so a
      // fixture installed before this line is overwritten, and Git execs the
      // retired shell publisher instead. Both tests in this group were green
      // that way, aimed at the wrong artifact.
      _installFixtureHook(gitDir, site.path, entity.name);

      final swap = git.updateRef(gitDir,
          ref: 'refs/heads/demo', newCommit: next, expected: tip);

      expect(swap.moved, isFalse,
          reason: 'a non-zero exit at prepared aborts the whole transaction');
      expect(git.revParse(gitDir, 'refs/heads/demo'), equals(tip),
          reason: 'the ref is where it was — the substrate is the witness, not '
              'our return value');
      expect(swap.report, contains("'prompt' is illegal here"),
          reason: "the gate's own sentence is the only account of why, and it "
              'rides the hook stderr Git carries up through update-ref');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('an act nobody gates lands, and wakes what is armed on it', () async {
      final tip = born('demo');
      final next = commit({'a': '1'}, parent: tip);
      final woken = File('${site.path}/woken');

      entity.on({EventPattern.parse('prompt.landed')},
          command: [
            _body(site, 'reactor', 'echo "\$BENTOS_COORD" > "${woken.path}"')
          ]);
      // After the arming — see above: arming rewrites the shim.
      _installFixtureHook(gitDir, site.path, entity.name);

      expect(
        git
            .updateRef(gitDir,
                ref: 'refs/heads/demo', newCommit: next, expected: tip)
            .moved,
        isTrue,
        reason: 'the falsifier for the test above: the same path with no gate '
            'on it must land, or the abort proved nothing but a broken hook',
      );
      await _settles(woken, within: const Duration(seconds: 30));
      expect(woken.readAsStringSync().trim(), equals('bentos.llm:demo'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

// ---------------------------------------------------------------------------

/// A real place on disk. No port is installed around it: the ambient already
/// **is** [ProcessGit], which is the point of this whole file.
Directory _place(String label) {
  final root = Directory(
      Directory.systemTemp.createTempSync(label).resolveSymbolicLinksSync());
  Directory('${root.path}/.place').createSync(recursive: true);
  File('${root.path}/.place/place.yaml').writeAsStringSync('name: $label\n');
  return root;
}

/// A body: a real program on disk, mode 755. Dispatch wakes commands and never
/// closures, so every listener in this file is one.
String _body(Directory site, String name, String script) {
  final file = File('${site.path}/$name.sh')
    ..writeAsStringSync('#!/usr/bin/env bash\nset -uo pipefail\n$script\n');
  Process.runSync('chmod', ['755', file.path]);
  return file.path;
}

/// Waits for a detached body's artifact. A `.landed` body outlives the process
/// that woke it, so the only honest proof it ran is the disk — never the return
/// of the caller that woke it.
Future<void> _settles(
  File artifact, {
  Duration within = const Duration(seconds: 10),
}) =>
    _settlesUntil(() => artifact.existsSync(),
        within: within, what: 'nothing appeared at ${artifact.path}');

Future<void> _settlesUntil(
  bool Function() done, {
  Duration within = const Duration(seconds: 10),
  String what = 'the condition never held',
}) async {
  final deadline = DateTime.now().add(within);
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('$what within $within');
}

/// **A publisher written for this file, and for nothing else.**
///
/// Not [referenceTransactionShimFor] and never derived from it. The shipped
/// shim is its own delivery with its own gates; what this proves is that Git
/// hands over the transaction and obeys the answer, and a fixture that borrowed
/// the real shim would leave the trampoline slice inheriting a witness aimed at
/// the wrong artifact.
///
/// It is deliberately the dumbest thing that can carry the contract: read the
/// phase from argv, the triples from stdin, hand both to [Entity.emit], exit
/// with what it returns.
void _installFixtureHook(String gitDir, String placePath, String name) {
  final caller = File(p.join(placePath, 'fixture_emit.dart'))
    ..writeAsStringSync('''
import 'dart:io';
import 'package:bentos_userland/entity.dart';

/// Test fixture. Stands where a publisher stands, and is not one.
Future<void> main(List<String> argv) async {
  const phases = {
    'prepared': EventPhase.attempted,
    'committed': EventPhase.landed,
    'aborted': EventPhase.refused,
  };
  final phase = phases[argv[1]];
  if (phase == null) exit(0);
  final updates = <TransactionRefUpdate>[];
  for (String? line = stdin.readLineSync();
      line != null;
      line = stdin.readLineSync()) {
    if (line.trim().isEmpty) continue;
    updates.add(TransactionRefUpdate.parse(line));
  }
  exit(await Entity(argv[2], from: argv[0]).emit(phase, updates));
}
''');

  final packages = p.join(Directory.current.path, '.dart_tool', 'package_config.json');
  final hook = File(p.join(gitDir, ArmingTables.hookPath))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
#!/usr/bin/env bash
# TEST FIXTURE. Not the shipped shim, and not derived from it.
exec dart run --packages='$packages' '${caller.path}' '$placePath' "\$1" '$name'
''');
  Process.runSync('chmod', ['755', hook.path]);
}
