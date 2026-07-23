import 'dart:io';

import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:bentos_userland/src/testing/run_in_memory_fs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem forget — acceptance', () {
    MemHabitat habitat() {
      final hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
      return hab;
    }

    Future<(String, String, int)> run(MemHabitat hab, List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        clock: hab.now,
        environment: {'BENTOS_AGENT': hab.bank},
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    bool exists(MemHabitat hab, String placePath, String topic) =>
        File(p.join(placePath, '${hab.bank}.mem', '$topic.md')).existsSync();

    test('forget <topic> removes the page and deletes its content', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'front', MemHabitat.page('prospective', '1.0', 'body'));
        final (out, _, code) = await run(hab, ['forget', '-p', '/hq/cto', 'front']);
        expect(code, 0);
        expect(exists(hab, '/hq/cto', 'front'), isFalse);
        expect(out, contains('forgot  front'));
      });
    });

    test('forget a b c removes all three', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'a', MemHabitat.page('prospective', '1.0', 'a'));
        hab.seed('/hq/cto', 'b', MemHabitat.page('prospective', '0.7', 'b'));
        hab.seed('/hq/cto', 'c', MemHabitat.page('prospective', '0.5', 'c'));
        final (_, _, code) = await run(hab, ['forget', '-p', '/hq/cto', 'a', 'b', 'c']);
        expect(code, 0);
        expect(exists(hab, '/hq/cto', 'a'), isFalse);
        expect(exists(hab, '/hq/cto', 'b'), isFalse);
        expect(exists(hab, '/hq/cto', 'c'), isFalse);
      });
    });

    test('one unknown topic fails the whole call atomically, deleting nothing', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq/cto', 'known', MemHabitat.page('prospective', '1.0', 'body'));
        final (out, err, code) = await run(hab, ['forget', '-p', '/hq/cto', 'known', 'ghost']);
        expect(code, 1);
        expect(err, contains('ghost'));
        expect(out, isEmpty);
        expect(exists(hab, '/hq/cto', 'known'), isTrue,
            reason: 'nothing deleted on a partial resolve');
      });
    });

    test('an inherited page is deleted at its home place', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'body'));
        final (_, _, code) = await run(hab, ['forget', '-p', '/hq/cto', 'founders']);
        expect(code, 0);
        expect(exists(hab, '/hq', 'founders'), isFalse);
      });
    });

    test('no topics is a usage error', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) = await run(hab, ['forget', '-p', '/hq/cto']);
        expect(code, 1);
        expect(err, contains('by name only'));
      });
    });

    test('a predicate selector is rejected (deletion is by name only)', () async {
      await runInMemoryFs((fs) async {
        final hab = habitat();
        final (_, err, code) = await run(hab, ['forget', '-p', '/hq/cto', '--tag', 'front']);
        expect(code, 64, reason: 'unknown option — forget takes no predicate');
        expect(err, isNotEmpty);
      });
    });
  });
}
