import 'package:bentos_userland/src/mem2/mem_runner.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('mem survey — acceptance', () {
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

    test('bare survey lists the whole cascaded map, grouped, 0.0 included', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '1.0', 'a'));
      hab.seed('/hq/cto', 'idle', MemHabitat.page('prospective', '0.0', 'b'));
      final (out, _, code) = await run(['survey', '-p', '/hq/cto']);
      expect(code, 0);
      expect(out, contains('founders'));
      expect(out, contains('idle'), reason: '0.0 is included in the bare map');
    });

    test('--warm selects the band, boundary inclusive', () async {
      hab.seed('/hq/cto', 'w7', MemHabitat.page('semantic', '0.7', 'a'));
      hab.seed('/hq/cto', 'w9', MemHabitat.page('semantic', '0.9', 'b'));
      hab.seed('/hq/cto', 'hot', MemHabitat.page('semantic', '1.0', 'c'));
      final (out, _, _) = await run(['survey', '-p', '/hq/cto', '--warm']);
      expect(out, contains('w7'));
      expect(out, contains('w9'));
      expect(out, isNot(contains('  1.0  hot')));
    });

    test('--type shows only that mode', () async {
      hab.seed('/hq/cto', 'sem', MemHabitat.page('semantic', '0.5', 'a'));
      hab.seed('/hq/cto', 'proc', MemHabitat.page('procedural', '0.5', 'b'));
      final (out, _, _) = await run(['survey', '-p', '/hq/cto', '--type', 'semantic']);
      expect(out, contains('sem'));
      expect(out, isNot(contains('proc')));
    });

    test('inherited pages carry @place', () async {
      hab.seed('/hq', 'founders', MemHabitat.page('semantic', '0.8', 'a'));
      final (out, _, _) = await run(['survey', '-p', '/hq/cto']);
      final ancestor = hab.resolver.enclosing('/hq');
      expect(out, contains('@${ancestor.name}'));
    });

    test('an empty map is begin-one guidance on stderr, exit 1', () async {
      final (out, err, code) = await run(['survey', '-p', '/hq/cto']);
      expect(out, isEmpty);
      expect(err, contains('no pages yet'));
      expect(code, 1);
    });

    test('absent agent with no \$BENTOS_AGENT errors with guidance', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final runner = MemRunner(
        out: out,
        err: err,
        fileSystem: hab.fs,
        clock: hab.now,
        home: hab.home,
        environment: const {},
      );
      await runner.run(['survey', '-p', '/hq/cto']);
      expect(err.toString(), contains('no agent'));
      expect(runner.exitCode, 1);
    });
  });
}
