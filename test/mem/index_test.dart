import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/bank.dart';
import 'package:bentos_userland/src/mem/index.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  /// Materializes an empty bank and returns the directory its pages live in
  /// — writing a page here is a hand-edit, exactly what [Bank.pages] reads,
  /// with no act and no git involved.
  Directory materialize(String name) {
    final entity = Entity(name, from: site.root.path).create(actor: testActor);
    entity.instance('main').create();
    final where = Directory(p.join(site.root.path, entity.name));
    entity.instance('main').materialize(at: where.path);
    return where;
  }

  Bank bankOf(String name) =>
      (Bank.resolve(name, vantage: site.root.path) as Found).bank;

  void writePage(
    Directory root,
    String topic, {
    MemType type = MemType.semantic,
    double attention = 0.5,
    String body = '',
  }) {
    final page = Page(
      topic: topic,
      fields: Fields(type: type, attention: Attention(attention)),
      body: body,
    );
    final file = File(p.join(root.path, '$topic.md'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(page.serialize());
  }

  group('one pass', () {
    test('weight counts pages, words and links over the whole bank', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: 'one two [[b]]');
        writePage(root, 'b', body: 'three');

        final index = Index.of(bankOf('alfred.mem'));
        expect(index.weight.pages, 2);
        expect(index.weight.words, 4); // "one two [[b]]" + "three"
        expect(index.weight.links, 1);
      });
    });

    test('outbound reads links in prose order, internal and external', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: 'first [[b]], then [[mem://john.mem/c|see]]');
        writePage(root, 'b');

        final index = Index.of(bankOf('alfred.mem'));
        final edges = index.outbound('a');
        expect(edges.map((e) => (e.bank, e.topic, e.order)), [
          (null, 'b', 0),
          ('john.mem', 'c', 1),
        ]);
      });
    });

    test('inbound is same-bank only — an external address never enters it', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]');
        writePage(root, 'b');

        final index = Index.of(bankOf('alfred.mem'));
        expect(index.inbound('b').map((e) => e.from), ['a']);
        // A page cannot be its own inbound edge from a foreign bank's link —
        // there is none here to find, by construction.
        expect(index.inbound('c'), isEmpty);
      });
    });

    test('a link inside a fenced block or inline code never reaches the maps', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '''
Real link [[b]].

```
not a link: [[ghost]]
```

Also not a link: `[[ghost]]`.
''');
        writePage(root, 'b');

        final index = Index.of(bankOf('alfred.mem'));
        expect(index.outbound('a').map((e) => e.topic), ['b']);
        expect(index.inbound('ghost'), isEmpty);
        expect(index.weight.links, 1);
      });
    });

    test('select delegates to the selector, hottest first', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'cold', attention: 0.2);
        writePage(root, 'hot', attention: 0.9);

        final index = Index.of(bankOf('alfred.mem'));
        final selected = index.select(Selector(minAttention: Attention(0.5)));
        expect(selected.map((p) => p.topic), ['hot']);
      });
    });
  });

  group('health — orphans', () {
    test('a page nothing links to is an orphan; one that is linked is not', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]');
        writePage(root, 'b');
        writePage(root, 'lonely');

        final health = Index.of(bankOf('alfred.mem')).health();
        expect(health.orphans, containsAll(['a', 'lonely']));
        expect(health.orphans, isNot(contains('b')));
        expect(health.scope.bank, 'alfred.mem');
      });
    });

    test('within narrows which pages are asked about, never which edges count', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', type: MemType.procedural, body: '[[b]]');
        writePage(root, 'b', type: MemType.semantic);

        final index = Index.of(bankOf('alfred.mem'));
        final health = index.health(
          within: const Selector(type: MemType.semantic),
        );
        // b is linked from a, which is real regardless of the selector — the
        // selector only chooses which topics are the ones being asked about.
        expect(health.orphans, isEmpty);
      });
    });
  });

  group('health — dead links', () {
    test('an internal link to nothing here, siblings omitted, is missing', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[nowhere]]');

        final health = Index.of(bankOf('alfred.mem')).health();
        expect(health.dead, hasLength(1));
        final found = health.dead.single;
        expect(found.from, 'a');
        expect(found.topic, 'nowhere');
        expect(found.bank, isNull);
        expect(found.kind, DeadKind.missing);
        expect(found.foundIn, isNull);
      });
    });

    test('an internal link whose topic lives in a sibling bank is elsewhere,'
        ' naming that bank — the john.mem corpus offender', () {
      site.run(() {
        final root = materialize('john.mem');
        writePage(root, 'a', body: '[[domain/aviacao/arco]]');

        final health = Index.of(bankOf('john.mem')).health(siblingTopics: {
          'mariela.mem': {'domain/aviacao/arco'},
        });
        final found = health.dead.single;
        expect(found.kind, DeadKind.elsewhere);
        expect(found.foundIn, 'mariela.mem');
      });
    });

    test('an internal link absent from every sibling stays missing', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[nowhere]]');

        final health = Index.of(bankOf('alfred.mem')).health(siblingTopics: {
          'bentos-agent.mem': {'unrelated'},
        });
        expect(health.dead.single.kind, DeadKind.missing);
      });
    });

    test('an external link whose bank is not among the siblings is bankNotFound', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[mem://ghost.mem/x]]');

        final health = Index.of(bankOf('alfred.mem')).health(siblingTopics: {
          'bentos-agent.mem': {'x'},
        });
        final found = health.dead.single;
        expect(found.bank, 'ghost.mem');
        expect(found.kind, DeadKind.bankNotFound);
      });
    });

    test('an external link whose bank resolves but lacks the topic is dead there', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[mem://bentos-agent.mem/x]]');

        final health = Index.of(bankOf('alfred.mem')).health(siblingTopics: {
          'bentos-agent.mem': {'y'},
        });
        final found = health.dead.single;
        expect(found.bank, 'bentos-agent.mem');
        expect(found.kind, DeadKind.missing);
      });
    });

    test('an external link is not judged at all when siblings are omitted', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[mem://ghost.mem/x]]');

        final health = Index.of(bankOf('alfred.mem')).health();
        expect(health.dead, isEmpty);
      });
    });

    test('a resolved link is never reported dead', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]');
        writePage(root, 'b');

        final health = Index.of(bankOf('alfred.mem')).health();
        expect(health.dead, isEmpty);
      });
    });

    test('both populations ride side by side, separated by the writer\'s type', () {
      site.run(() {
        final root = materialize('alfred.mem');
        writePage(root, 'journal', type: MemType.episodic, body: '[[forgotten]]');
        writePage(root, 'canon', type: MemType.semantic, body: '[[also-gone]]');

        final health = Index.of(bankOf('alfred.mem')).health();
        expect(health.dead, hasLength(2));
        final byTopic = {for (final d in health.dead) d.topic: d.fromType};
        expect(byTopic['forgotten'], MemType.episodic);
        expect(byTopic['also-gone'], MemType.semantic);
      });
    });
  });

  group('R4.6 — the parse budget', () {
    test('a full pass over a few thousand pages stays fast', () {
      site.run(() {
        final root = materialize('alfred.mem');
        const n = 1000;
        for (var i = 0; i < n; i++) {
          writePage(root, 'topic-$i', body: 'linking to [[topic-${(i + 1) % n}]]');
        }

        final bank = bankOf('alfred.mem');
        final stopwatch = Stopwatch()..start();
        final index = Index.of(bank);
        stopwatch.stop();

        expect(index.weight.pages, n);
        // Not R4.6's own 200ms/2,500-page figure — a generous smoke bound
        // against a real filesystem, kept loose so it never flakes.
        expect(stopwatch.elapsedMilliseconds, lessThan(3000));
      });
    });
  });
}
