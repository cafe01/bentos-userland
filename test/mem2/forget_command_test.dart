import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem forget — acceptance', () {
    late MemHabitat hab;

    setUp(() {
      hab = MemHabitat();
      hab.place('/hq');
      hab.place('/hq/cto');
    });

    Future<(String, String, int)> run(List<String> args) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        fileSystem: hab.fs,
        clock: hab.now,
        home: hab.home,
        environment: {'BENTOS_AGENT': hab.entity},
      );
      await runner.run(args);
      return (out.toString(), err.toString(), runner.exitCode);
    }

    bool exists(String placePath, String topic) => hab.fs
        .file(hab.fs.path.join(placePath, '.place', 'mem', hab.entity, '$topic.md'))
        .existsSync();

    test('forget <topic> removes the page and deletes its content', () async {
      hab.seed('/hq/cto', 'front', MemHabitat.page('prospective', '1.0', 'body'));
      final (out, _, code) = await run(['forget', '-p', '/hq/cto', 'front']);
      expect(code, 0);
      expect(exists('/hq/cto', 'front'), isFalse);
      expect(out, contains('forgot  front'));
    });

    test('forget a b c removes all three', () async {
      hab.seed('/hq/cto', 'a', MemHabitat.page('prospective', '1.0', 'a'));
      hab.seed('/hq/cto', 'b', MemHabitat.page('prospective', '0.7', 'b'));
      hab.seed('/hq/cto', 'c', MemHabitat.page('prospective', '0.5', 'c'));
      final (_, _, code) = await run(['forget', '-p', '/hq/cto', 'a', 'b', 'c']);
      expect(code, 0);
      expect(exists('/hq/cto', 'a'), isFalse);
      expect(exists('/hq/cto', 'b'), isFalse);
      expect(exists('/hq/cto', 'c'), isFalse);
    });

    test('one unknown topic fails the whole call atomically, deleting nothing', () async {
      hab.seed('/hq/cto', 'known', MemHabitat.page('prospective', '1.0', 'body'));
      final (out, err, code) = await run(['forget', '-p', '/hq/cto', 'known', 'ghost']);
      expect(code, 1);
      expect(err, contains('ghost'));
      expect(out, isEmpty);
      expect(exists('/hq/cto', 'known'), isTrue, reason: 'nothing deleted on a partial resolve');
    });

    test('an inherited page is deleted at its home place', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'body'));
      final (_, _, code) = await run(['forget', '-p', '/hq/cto', 'founders']);
      expect(code, 0);
      expect(exists('/hq', 'founders'), isFalse);
    });

    test('no topics is a usage error', () async {
      final (_, err, code) = await run(['forget', '-p', '/hq/cto']);
      expect(code, 1);
      expect(err, contains('by name only'));
    });

    test('a predicate selector is rejected (deletion is by name only)', () async {
      final (_, err, code) = await run(['forget', '-p', '/hq/cto', '--tag', 'front']);
      expect(code, 64, reason: 'unknown option — forget takes no predicate');
      expect(err, isNotEmpty);
    });
  });
}
