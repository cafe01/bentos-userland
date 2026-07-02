import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem recall — acceptance', () {
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

    test('recall <topic> prints one page in full under its rule', () async {
      hab.seed('/hq/cto', 'agency/spawn',
          MemHabitat.page('procedural', '0.7', 'the keystone body'));
      final (out, _, code) = await run(['recall', '-p', '/hq/cto', 'agency/spawn']);
      expect(code, 0);
      expect(out, contains('agency/spawn  ·  procedural  ·  a:0.7'));
      expect(out, contains('the keystone body'));
    });

    test('recall a b prints both, separated', () async {
      hab.seed('/hq/cto', 'a', MemHabitat.page('semantic', '0.5', 'body-a'));
      hab.seed('/hq/cto', 'b', MemHabitat.page('semantic', '0.5', 'body-b'));
      final (out, _, _) = await run(['recall', '-p', '/hq/cto', 'a', 'b']);
      expect(out, contains('body-a'));
      expect(out, contains('body-b'));
      expect(RegExp('^─+\$', multiLine: true).allMatches(out), hasLength(2));
    });

    test('recall --hot pulls the full bodies of the 1.0 band (the wake read)', () async {
      hab.seed('/hq/cto', 'live', MemHabitat.page('autobiographical', '1.0', 'hot body'));
      hab.seed('/hq/cto', 'cold', MemHabitat.page('semantic', '0.3', 'cold body'));
      final (out, _, _) = await run(['recall', '-p', '/hq/cto', '--hot']);
      expect(out, contains('hot body'));
      expect(out, isNot(contains('cold body')));
    });

    test('a cascaded topic resolves from an ancestor place', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'ancestor body'));
      final (out, _, code) = await run(['recall', '-p', '/hq/cto', 'founders']);
      expect(code, 0);
      expect(out, contains('ancestor body'));
    });

    test('multi-topic recall with one unknown fails atomically, prints nothing', () async {
      hab.seed('/hq/cto', 'known', MemHabitat.page('semantic', '0.5', 'body'));
      final (out, err, code) = await run(['recall', '-p', '/hq/cto', 'known', 'ghost']);
      expect(out, isEmpty, reason: 'nothing prints on a partial resolve');
      expect(err, contains('ghost'));
      expect(code, 1);
    });
  });
}
