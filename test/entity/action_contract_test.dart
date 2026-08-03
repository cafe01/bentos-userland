import 'dart:io';

import 'package:bentos_userland/entity.dart';
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
      llm = Entity('bentos.llm', from: site.root.path).create();
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
          }, actor: const Actor('alfred')));

  group('an instance is born from a commit', () {
    test('from genesis by default — empty the way a constructor leaves one', () {
      site.run(() {
        expect(llm.instance('s1').tip, isNotNull);
        expect(llm.instance('s1').log, isEmpty);
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
        expect(llm.instance('s2').log.length, 1);
      });
      await writeAct(site.run(() => llm.instance('s2')), 'reply', 'answer');
      site.run(() {
        expect(llm.instance('s1').log.length, 1, reason: 'instances do not interfere');
        expect(llm.instance('s2').log.length, 2);
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
            })),
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
            }));
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
    test('two bodies reading tip A: exactly one lands, the loser is refused', () {
      // Deterministic by construction: both areas are opened at the same tip
      // before either commits, which is precisely the race the swap exists for.
      site.run(() {
        final instance = llm.instance('s1');
        final mine = instance.beginAct();
        final yours = instance.beginAct();
        expect(mine.expectedTip, yours.expectedTip);

        File(p.join(mine.directory.path, 'mine.txt')).writeAsStringSync('mine');
        File(p.join(yours.directory.path, 'yours.txt')).writeAsStringSync('yours');

        final first = mine.commit('prompt', actor: const Actor('alfred'));
        final second = yours.commit('prompt', actor: const Actor('cafe'));

        expect(first, isA<Landed>());
        expect(second, isA<Refused>());
        expect((second as Refused).expected, mine.expectedTip);
        expect(second.found, (first as Landed).action.commit);

        mine.release();
        yours.release();
      });
    });

    test('refusal is a value, never a throw', () {
      site.run(() {
        final ws = llm.instance('s1').beginAct();
        llm.instance('s1').beginAct().commit('prompt');
        expect(() => ws.commit('prompt'), returnsNormally);
      });
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
        expect(llm.instance('s3').log, isEmpty);
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
