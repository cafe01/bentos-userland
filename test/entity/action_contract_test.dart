import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/entity.dart' show gitDirOf;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

/// **Tier A — the action.** The primitive's whole weight sits here: an act is a
/// write in a private area landed by compare-and-swap, and the negatives matter
/// as much as the positives.
void main() {
  late Site site;
  late Entity llm;

  setUp(() {
    site = Site();
    site.run(() {
      llm = Entity('bentos.llm', from: site.root.path).create(actor: testActor);
      llm.instance('s1').create();
    });
  });

  tearDown(() => site.dispose());

  Future<ActionResult> writeAct(
    Instance instance,
    String action,
    String content, {
    String file = 'messages/1.txt',
  }) =>
      site.runAsync(() => instance.act(action, (ws) {
            File(p.join(ws.directory.path, file))
              ..parent.createSync(recursive: true)
              ..writeAsStringSync(content);
          }, actor: Actor('alfred', email: 'alfred@test.local')));

  group('an instance is born from a commit', () {
    test('from genesis by default — empty the way a constructor leaves one', () {
      site.run(() {
        expect(llm.instance('s1').tip, isNotNull);
        expect(llm.instance('s1').log(), isEmpty);
      });
    });

    test('a handle to an unborn instance has a null tip', () {
      site.run(() => expect(llm.instance('never').tip, isNull));
    });

    test('a fork inherits a lived past, and the two lines do not interfere', () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      site.run(() {
        final tip = llm.instance('s1').tip!;
        llm.instance('s2').create(from: tip);
        expect(llm.instance('s2').log().length, 1);
      });
      await writeAct(site.run(() => llm.instance('s2')), 'reply', 'answer');
      site.run(() {
        expect(llm.instance('s1').log().length, 1, reason: 'instances do not interfere');
        expect(llm.instance('s2').log().length, 2);
      });
    });
  });

  group('the act', () {
    test('lands, and the commit is the action', () async {
      final result = await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      expect(result, isA<Landed>());
      final action = (result as Landed).action;
      expect(action.name, 'prompt');
      expect(action.actor.name, 'alfred');
      expect(action.diff().paths, ['messages/1.txt']);
    });

    test('the bracket releases its area even when the body throws', () async {
      late Directory area;
      await expectLater(
        site.runAsync(() => llm.instance('s1').act('prompt', (ws) {
              area = ws.directory;
              throw StateError('the body failed');
            }, actor: testActor)),
        throwsA(isA<StateError>()),
      );
      expect(
        area.existsSync(),
        isFalse,
        reason: 'Dart has no destructor, so the bracket owns the lifetime',
      );
    });

    test('each act writes in an area of its own', () async {
      final areas = <String>[];
      for (var i = 0; i < 2; i++) {
        await site.runAsync(() => llm.instance('s1').act('prompt', (ws) {
              areas.add(ws.directory.path);
              File(p.join(ws.directory.path, 'm$i.txt')).writeAsStringSync('x');
            }, actor: testActor));
      }
      expect(
        areas.first,
        isNot(areas.last),
        reason: 'a shared worktree corrupts payloads before the swap can see it',
      );
    });

    test('content is read at the ref, with no worktree', () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      site.run(() {
        expect(
          String.fromCharCodes(llm.instance('s1').read('messages/1.txt')),
          'hello',
        );
      });
    });

    test('a tree is listed at the ref, one level, sorted', () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'a',
          file: 'messages/0002.txt');
      await writeAct(site.run(() => llm.instance('s1')), 'reply', 'b',
          file: 'messages/0001.txt');
      await writeAct(site.run(() => llm.instance('s1')), 'note', 'c',
          file: 'meta/card.json');
      site.run(() {
        // The listing a folded machine lives on: the names under one directory,
        // in the order the substrate keeps them, and nothing from elsewhere.
        expect(
          llm.instance('s1').ls('messages'),
          equals(['messages/0001.txt', 'messages/0002.txt']),
        );
        expect(
          llm.instance('s1').ls(''),
          equals(['messages', 'meta']),
          reason: 'the root lists directories, one level deep',
        );
        expect(llm.instance('s1').ls('nowhere'), isEmpty,
            reason: 'a path that is not there is an answer, not a failure');
      });
    });

    test('both readings answer at a point in history, not only the present', () async {
      // What a validator asks: *was this legal where it was taken*. It stands at
      // the parent of the commit landing, which is never the tip.
      final first = await writeAct(
          site.run(() => llm.instance('s1')), 'prompt', 'hello',
          file: 'messages/0001.txt') as Landed;
      await writeAct(site.run(() => llm.instance('s1')), 'reply', 'answer',
          file: 'messages/0002.txt');

      site.run(() {
        final s1 = llm.instance('s1');
        expect(s1.ls('messages'), hasLength(2), reason: 'the present');
        expect(
          s1.ls('messages', at: first.action.commit),
          equals(['messages/0001.txt']),
          reason: 'and the past, which is a different answer',
        );
        expect(
          String.fromCharCodes(
              s1.read('messages/0001.txt', at: first.action.commit)),
          'hello',
        );
      });
    });
  });

  group('the compare-and-swap', () {
    test('two bodies reading tip A: exactly one lands, the loser is contested',
        () {
      // Deterministic by construction: both areas are opened at the same tip
      // before either commits, which is precisely the race the swap exists for.
      site.run(() {
        final instance = llm.instance('s1');
        final mine = instance.beginAct();
        final yours = instance.beginAct();
        expect(mine.expectedTip, yours.expectedTip);

        File(p.join(mine.directory.path, 'mine.txt')).writeAsStringSync('mine');
        File(p.join(yours.directory.path, 'yours.txt')).writeAsStringSync('yours');

        final first = mine.commit('prompt', actor: Actor('alfred', email: 'alfred@test.local'));
        final second = yours.commit('prompt', actor: Actor('cafe', email: 'cafe@test.local'));

        expect(first, isA<Landed>());
        // **Contested and not barred**: nobody decided anything, the ref simply
        // moved. The loser re-reads the tip and retries, and that terminates.
        expect(second, isA<Contested>());
        expect((second as Contested).expected, mine.expectedTip);
        expect(second.found, (first as Landed).action.commit);

        mine.release();
        yours.release();
      });
    });

    test('a gate refusing is reported in the gate\'s own words', () {
      site.run(() {
        final ws = llm.instance('s1').beginAct();
        File(p.join(ws.directory.path, 'prompt.txt')).writeAsStringSync('hi');
        // A gate stands at this swap and says no. Nothing about the ref is
        // wrong — it holds exactly what the act was cut from.
        site.git.declineNextSwap = 'entity: refused by r4: bin/check\n'
            "check: bentos.llm:s1: 'prompt' is illegal at owes_inference";

        final result = ws.commit('prompt', actor: Actor('alfred', email: 'alfred@test.local'));

        // A gate spoke, so this is barred and never contested: the same act
        // will be barred again, and a retry loop here is an infinite loop
        // wearing a retry policy.
        expect(result, isA<Barred>());
        final barred = result as Barred;
        expect(barred.reason, contains('illegal at owes_inference'),
            reason: 'the sentence a person needs is the gate\'s, not ours');
        expect(barred.reason, contains('refused by r4'),
            reason: 'and which registration refused it');
        expect(barred.reason, isNot(contains('entity: refused by')),
            reason: 'the program is named once, by whoever prints this');
        // **The half that was wrong before**, now unrepresentable rather than
        // merely unasserted: a gate refusal is not about the ref, and `Barred`
        // carries no tips at all, so nothing can invite a reader to compare two
        // values the way the guess that printed `expected b71043a, found
        // b71043a` did.
        expect(llm.instance('s1').tip, ws.expectedTip,
            reason: 'a refused act leaves the ref exactly where it stood');
        ws.release();
      });
    });

    test('refusal is a value, never a throw', () {
      site.run(() {
        final ws = llm.instance('s1').beginAct();
        llm.instance('s1').beginAct().commit('prompt', actor: testActor);
        expect(() => ws.commit('prompt', actor: testActor), returnsNormally);
      });
    });
  });

  group('the legible sentence', () {
    Future<Action> sayingAct(String? say) async {
      final landed = await site.runAsync(
        () => llm.instance('s1').act(
              'prompt',
              (ws) => File(p.join(ws.directory.path, 'm.txt'))
                  .writeAsStringSync('hello'),
              actor: Actor('cafe', email: 'cafe@test.local'),
              say: say,
            ),
      ) as Landed;
      return landed.action;
    }

    test('rides along with the act and comes back whole', () async {
      final act = await sayingAct('user say');
      expect(act.sentence, 'user say');
      expect(act.name, 'prompt', reason: 'the noun is untouched by it');
    });

    test('an act that said nothing has no sentence', () async {
      expect(await sayingAct(null).then((a) => a.sentence), isNull);
      expect(
        await sayingAct('   ').then((a) => a.sentence),
        isNull,
        reason: 'blank is the same as absent, never an empty sentence',
      );
    });

    test('it is normalized to one line, because a trailer is a line', () {
      expect(Action.sayOneLine('user\nsay'), 'user say');
      expect(
        Action.sayIn(Action.messageFor('prompt', say: 'user\nsay')),
        'user say',
        reason: 'a newline in the trailer would truncate what is read back',
      );
    });

    test('the subject carries it, so `log --oneline` reads as the actor', () {
      expect(
        Action.messageFor('prompt', say: 'user say').split('\n').first,
        'user say',
      );
      expect(
        Action.messageFor('prompt').split('\n').first,
        'prompt',
        reason: 'with nothing said, the noun is still the subject',
      );
    });

    test('the substrate reads the noun and never the sentence', () async {
      // The sentence is stored, printed and never interpreted — so a sentence
      // that spells another noun changes nothing about what matched.
      final act = await sayingAct('reply');
      expect(act.name, 'prompt');
    });
  });

  group('what an act is not', () {
    test('acting never wakes a listener in process', () async {
      final witness = File(p.join(site.root.path, 'woken'));
      site.run(() => llm.on(
            {EventPattern.parse('prompt.landed')},
            command: ['touch', witness.path],
          ));

      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');

      expect(
        witness.existsSync(),
        isFalse,
        reason: 'waking is the shim\'s, at the ref transaction — never the API\'s',
      );
    });

    test('there is no verb that asks an entity to do something', () {
      final surface = llm as dynamic;
      expect(() => surface.invoke('prompt'), throwsA(isA<NoSuchMethodError>()));
      expect(() => surface.run('prompt'), throwsA(isA<NoSuchMethodError>()));
    });

    test('birthing an instance is not an act and leaves no action', () {
      site.run(() {
        llm.instance('s3').create();
        expect(llm.instance('s3').log(), isEmpty);
      });
    });

    test(
        'a genesis advanced more than once leaves none of its own commits in '
        'the log — excluding only the tip would leak the rest', () async {
      // Genesis re-authored twice *before* the instance forks from it: every
      // one of those commits is an ancestor of the instance, and only the
      // present tip is the single sha "exclude the tip" would catch.
      final gitDir = gitDirOf(llm);
      Commit advanceGenesis() {
        final held = site.git.revParse(gitDir, Entity.genesisRef);
        final work = Directory.systemTemp.createTempSync('entity_genesis-');
        try {
          final tree = site.git.writeTree(gitDir, workTree: work.path);
          final sha = site.git.commitTree(
            gitDir,
            tree: tree,
            parents: [if (held != null) held.sha],
            message: 'a version published upstream\n',
          actor: testActor,
          );
          site.git.updateRef(
            gitDir,
            ref: Entity.genesisRef,
            newCommit: Commit(sha),
            expected: held,
          );
          return Commit(sha);
        } finally {
          work.deleteSync(recursive: true);
        }
      }

      site.run(advanceGenesis);
      site.run(advanceGenesis);
      site.run(() => llm.instance('s4').create());

      await writeAct(site.run(() => llm.instance('s4')), 'prompt', 'hello');

      final log = site.run(() => llm.instance('s4').log());
      expect(log, hasLength(1), reason: 'genesis was advanced twice after '
          'the fork point; excluding only its present tip would leave the '
          'earlier authoring commit standing in as if it were an act');
      expect(log.single.name, equals('prompt'));
    });
  });

  group('the incremental read — since', () {
    test('a delta of only what landed after the cursor', () async {
      final instance = site.run(() => llm.instance('s1'));
      await writeAct(instance, 'prompt', 'one', file: 'messages/1.txt');
      await writeAct(instance, 'reply', 'two', file: 'messages/2.txt');
      final cursor = site.run(() => llm.instance('s1').log().first.commit);
      await writeAct(instance, 'note', 'three', file: 'messages/3.txt');

      site.run(() {
        final full = llm.instance('s1').log();
        final delta = llm.instance('s1').log(since: cursor);
        expect(full, hasLength(3), reason: 'the whole history, for reference');
        expect(delta.map((a) => a.commit.sha), [full.first.commit.sha],
            reason: 'exactly the one act that landed after the cursor');
      });
    });

    test('empty when the cursor already is the tip', () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      site.run(() {
        final tip = llm.instance('s1').log().first.commit;
        expect(llm.instance('s1').log(since: tip), isEmpty);
      });
    });

    test('a fork accepts a commit from the parent\'s line as a legal cursor',
        () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      final forkPoint = site.run(() => llm.instance('s1').tip!);
      site.run(() => llm.instance('s2').create(from: forkPoint));
      await writeAct(site.run(() => llm.instance('s2')), 'reply', 'answer');

      site.run(() {
        final delta = llm.instance('s2').log(since: forkPoint);
        expect(delta.single.name, 'reply',
            reason: 'the inherited past is not new, only what s2 itself did');
      });
    });

    test('still excludes genesis with a cursor given', () async {
      final gitDir = gitDirOf(llm);
      final held = site.run(() => site.git.revParse(gitDir, Entity.genesisRef));
      final work = Directory.systemTemp.createTempSync('entity_genesis-');
      try {
        site.run(() {
          final tree = site.git.writeTree(gitDir, workTree: work.path);
          final sha = site.git.commitTree(gitDir,
              tree: tree, parents: [if (held != null) held.sha], message: 'x\n', actor: testActor);
          site.git.updateRef(gitDir,
              ref: Entity.genesisRef, newCommit: Commit(sha), expected: held);
        });
      } finally {
        work.deleteSync(recursive: true);
      }
      site.run(() => llm.instance('s5').create());
      final first =
          await writeAct(site.run(() => llm.instance('s5')), 'prompt', 'hi');
      final cursor = (first as Landed).action.commit;
      site.run(() {
        // A cursor that happens to equal genesis's own tip must still resolve
        // to an empty delta, never to genesis's authoring commit surfacing as
        // an act because the explicit genesis exclusion was dropped in favour
        // of the cursor.
        expect(llm.instance('s5').log(since: cursor), isEmpty);
      });
    });
  });

  group('materialization is a condition, not a property', () {
    test('an instance exists with no worktree, and is put into one on demand', () async {
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      site.run(() {
        final face = llm.instance('s1').materialize();
        expect(File(p.join(face.directory.path, 'messages/1.txt')).existsSync(), isTrue);
        face.release();
        expect(face.directory.existsSync(), isFalse);
      });
    });

    test('a persistent worktree lags, and refreshing is the looker\'s duty', () async {
      final face = site.run(() => llm.instance('s1').materialize());
      final at = site.run(() => face.at);
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      site.run(() {
        expect(face.at, at, reason: 'nothing refreshes a face for it');
        face.refresh();
        expect(face.at, llm.instance('s1').tip);
      });
    });
  });
}
