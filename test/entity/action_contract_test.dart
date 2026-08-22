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

    test('a throwing body unwinds the tree rather than losing it', () async {
      late Directory area;
      await expectLater(
        site.runAsync(() => llm.instance('s1').act('prompt', (ws) {
              area = ws.directory;
              throw StateError('the body failed');
            }, actor: testActor)),
        throwsA(isA<ActUnwound>()
            .having((e) => e.cause, 'cause', isA<StateError>())),
      );
      expect(
        area.existsSync(),
        isTrue,
        reason: "the tree is the instance's own, standing before the body ran "
            'and after it failed — there is no private area to release, only '
            'a ledger the failed write must not reach',
      );
    });

    test('two acts on one instance write in the same tree, reused', () async {
      final areas = <String>[];
      for (var i = 0; i < 2; i++) {
        await site.runAsync(() => llm.instance('s1').act('prompt', (ws) {
              areas.add(ws.directory.path);
              File(p.join(ws.directory.path, 'm$i.txt')).writeAsStringSync('x');
            }, actor: testActor));
      }
      expect(
        areas.first,
        areas.last,
        reason: 'one attached tree per instance — an act commits where the '
            'instance already stands rather than standing a second one up',
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
      // The instance's own tree does not lag — an act commits in it, so
      // asking for it at no address, or at the address it already stands at,
      // hands back the very tree the next act writes into. A genuine face is
      // asked for **elsewhere**: detached by construction, and the one tree
      // this law still lets fall behind.
      await writeAct(site.run(() => llm.instance('s1')), 'prompt', 'hello');
      final where = p.join(site.root.path, 'face');
      final face = site.run(() {
        final m = llm.instance('s1').materialization(where);
        m.refresh();
        return m;
      });
      final at = site.run(() => face.at);
      await writeAct(site.run(() => llm.instance('s1')), 'reply', 'world');
      site.run(() {
        expect(face.at, at, reason: 'nothing refreshes a face for it');
        face.refresh();
        expect(face.at, llm.instance('s1').tip);
      });
    });

    test('refreshing an unstood instance at its own address attaches it',
        () async {
      // Standing an absent tree up and putting the instance into the
      // materialized condition are the same act at this one address. A
      // detached tree stood up here by mistake would meet the next act's own
      // refusal of a tree it does not follow — [WorktreeUnattached] — so the
      // address itself is what tells `refresh` to attach rather than the
      // caller's intent, which it cannot see.
      site.run(() => llm.instance('s2').create());
      final address = site.run(() => llm.instance('s2').conventionAddress);
      site.run(() => llm.instance('s2').materialization(address).refresh());

      final result = await writeAct(site.run(() => llm.instance('s2')), 'prompt', 'hello');
      expect(result, isA<Landed>());
      site.run(() {
        expect(File(p.join(address, 'messages/1.txt')).existsSync(), isTrue);
      });
    });
  });
}
