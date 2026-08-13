import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/mem/attention.dart';
import 'package:bentos_userland/src/mem/page.dart';
import 'package:bentos_userland/src/mem/walk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../entity/helpers.dart';

void main() {
  late Site site;

  setUp(() => site = Site());
  tearDown(() => site.dispose());

  /// Materializes an empty bank and returns the directory its pages live in
  /// — no land, no act, exactly the hand-edit shape [Bank.pages] reads.
  Directory materialize(String name) {
    final entity = Entity(name, from: site.root.path).create(actor: testActor);
    entity.instance('main').create();
    final where = Directory(p.join(site.root.path, entity.name));
    entity.instance('main').materialize(at: where.path);
    return where;
  }

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

  group('single bank, level by level', () {
    test('an entry with no links returns just itself', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a']);
        expect(walked.skipped, isEmpty);
        expect(walked.weight.pages, 1);
        expect(walked.weight.links, 0);
      });
    });

    test('links are followed outward, prose order first, depth 1 before depth 2', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: 'first [[c]], then [[b]]');
        writePage(root, 'b', body: '[[d]]');
        writePage(root, 'c', body: '[[e]]');
        writePage(root, 'd');
        writePage(root, 'e');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        // a first; then its links in prose order (c, b) — both depth 1 —
        // before either of their own children (e, d) — depth 2.
        expect(walked.pages.map((p) => p.topic), ['a', 'c', 'b', 'e', 'd']);
        expect(walked.weight.links, 4);
      });
    });

    test('a page reached by two routes is returned once, at the first reach', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]] [[c]]');
        writePage(root, 'b', body: '[[d]]');
        writePage(root, 'c', body: '[[d]]');
        writePage(root, 'd');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a', 'b', 'c', 'd']);
        expect(walked.pages.where((p) => p.topic == 'd'), hasLength(1));
      });
    });

    test('a dead link is reported and not returned', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[nowhere]]');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a']);
        final skip = walked.skipped.single;
        expect(skip.address, const Address(bank: 'alfred.mem', topic: 'nowhere'));
        expect(skip.from, 'a');
        expect(skip.reason, SkipReason.dead);
      });
    });

    test('a dead entry point is reported with no referrer', () async {
      await site.runAsync(() async {
        materialize('alfred.mem');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'ghost')]);

        expect(walked.pages, isEmpty);
        final skip = walked.skipped.single;
        expect(skip.from, isNull);
        expect(skip.reason, SkipReason.dead);
      });
    });
  });

  group('depth', () {
    test('depth 0 returns only the entries, and reports their links as too deep', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]');
        writePage(root, 'b');

        final walk = Walk(vantage: site.root.path, depth: 0);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a']);
        expect(walked.skipped.single.reason, SkipReason.tooDeep);
        expect(walked.skipped.single.address.topic, 'b');
      });
    });

    test('depth 1 reaches direct links but not their own links', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]');
        writePage(root, 'b', body: '[[c]]');
        writePage(root, 'c');

        final walk = Walk(vantage: site.root.path, depth: 1);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a', 'b']);
        expect(walked.skipped.single.reason, SkipReason.tooDeep);
      });
    });
  });

  group('the filter', () {
    test('an excluded page is not returned and its own links are not followed', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[b]]', type: MemType.procedural);
        writePage(root, 'b', body: '[[c]]', type: MemType.semantic);
        writePage(root, 'c', type: MemType.procedural);

        final walk = Walk(
          vantage: site.root.path,
          filter: const Selector(type: MemType.procedural),
        );
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a']);
        expect(walked.skipped.single.address.topic, 'b');
        expect(walked.skipped.single.reason, SkipReason.filtered);
        // c was never reached — b's link was never followed.
        expect(walked.pages.any((p) => p.topic == 'c'), isFalse);
      });
    });
  });

  group('cross-bank', () {
    test('the current bank finishes before a foreign bank begins, no interleaving', () async {
      await site.runAsync(() async {
        final rootA = materialize('alfred.mem');
        writePage(rootA, 'a', body: 'first [[mem://john.mem/x|x]], then [[b]]');
        writePage(rootA, 'b');

        final rootB = materialize('john.mem');
        writePage(rootB, 'x', body: '[[y]]');
        writePage(rootB, 'y');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        // alfred.mem's own reachable set (a, b) completes before john.mem
        // (x, then its own child y) begins, even though x was named first.
        expect(walked.pages.map((p) => p.topic), ['a', 'b', 'x', 'y']);
      });
    });

    test('a bank that does not resolve from the vantage is reported and the walk continues', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: '[[mem://ghost.mem/x]] then [[b]]');
        writePage(root, 'b');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.pages.map((p) => p.topic), ['a', 'b']);
        final skip = walked.skipped.single;
        expect(skip.address, const Address(bank: 'ghost.mem', topic: 'x'));
        expect(skip.from, 'a');
        expect(skip.reason, SkipReason.bankNotFound);
      });
    });

    test('entry points across two banks each walk their own bank fully', () async {
      await site.runAsync(() async {
        final rootA = materialize('alfred.mem');
        writePage(rootA, 'a', body: '[[a2]]');
        writePage(rootA, 'a2');

        final rootB = materialize('john.mem');
        writePage(rootB, 'b', body: '[[b2]]');
        writePage(rootB, 'b2');

        final walk = Walk(vantage: site.root.path);
        final walked = await walk.from([
          const Address(bank: 'alfred.mem', topic: 'a'),
          const Address(bank: 'john.mem', topic: 'b'),
        ]);

        expect(walked.pages.map((p) => p.topic), ['a', 'a2', 'b', 'b2']);
      });
    });
  });

  group('weight', () {
    test('reports pages, words returned, and links followed — not links seen', () async {
      await site.runAsync(() async {
        final root = materialize('alfred.mem');
        writePage(root, 'a', body: 'one two [[b]]', type: MemType.procedural);
        writePage(root, 'b', body: 'three');

        final walk = Walk(
          vantage: site.root.path,
          filter: const Selector(type: MemType.procedural),
        );
        final walked = await walk.from([const Address(bank: 'alfred.mem', topic: 'a')]);

        expect(walked.weight.pages, 1);
        expect(walked.weight.words, 3); // "one two [[b]]" only — b was filtered
        expect(walked.weight.links, 1); // followed, even though b did not pass
      });
    });
  });

  group('Address', () {
    test('parses and renders the mem:// form', () {
      final address = Address.parse('mem://alfred.mem/domain/x');
      expect(address, const Address(bank: 'alfred.mem', topic: 'domain/x'));
      expect(address.toString(), 'mem://alfred.mem/domain/x');
    });

    test('a string with no mem:// prefix does not parse', () {
      expect(Address.parse('domain/x'), isNull);
    });
  });
}
