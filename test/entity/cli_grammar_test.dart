import 'dart:async';

import 'package:bentos_userland/entity.dart';
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// `--help` answers through `print`, not through the sink [Cli.run] hands
/// the runner — the args package's own [Command.printUsage] calls the global
/// function directly. Captured the same way a real terminal would see it,
/// rather than reached for through the library's internals.
Future<String> printedBy(Future<void> Function() body) async {
  final buffer = StringBuffer();
  await runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => buffer.writeln(line),
    ),
  );
  return buffer.toString();
}

void main() {
  late Site site;
  late Cli cli;

  setUp(() {
    site = Site();
    cli = Cli(site);
  });
  tearDown(() => site.dispose());

  group('invocation — the grammar `--help` prints, one declaration per verb',
      () {
    // Every verb the runner registers, and the exact line it must teach —
    // the cure for `entity refresh <coord> <path>` learned by failing twice.
    // Positionals only: options are already listed under the line by the
    // args package itself, and duplicating them here would test that
    // package, not this declaration.
    const grammar = {
      'create': 'create <name>',
      'install': 'install <source>',
      'refit': 'refit <name>',
      'upgrade': 'upgrade <name>',
      'which': 'which <name>',
      'info': 'info <name>',
      'publish': 'publish <name> <remote>',
      'fetch': 'fetch <coord> <remote>',
      'remotes': 'remotes <name>',
      'new': 'new <name> <instance>',
      'ls': 'ls <name|coord[:path]>',
      'log': 'log <coord>',
      'show': 'show <coord> <action>',
      'act': 'act <coord> <action> -- <command>',
      'run': 'run <coord> <function> [args...]',
      'read': 'read <coord:path>',
      'materialize': 'materialize <coord>',
      'refresh': 'refresh <coord> <path>',
      'on': 'on <coord> <event[,event]> -- <command>',
      'once': 'once <coord> <event[,event]> -- <command>',
      'off': 'off <coord> <id>',
      'listeners': 'listeners <coord>',
      'listen': 'listen <name> <event[,event]>',
      'deliveries': 'deliveries <name> <event[,event]>',
      'resolve': 'resolve <coord>',
      'tip': 'tip <coord>',
      'path': 'path <name>',
      'release': 'release <path>',
      'emit': 'emit <name> <phase>',
    };

    for (final entry in grammar.entries) {
      test('`entity ${entry.key}` prints its own positionals, not a generic '
          '[arguments]', () async {
        final printed = await printedBy(() => cli.run([entry.key, '--help']));
        expect(printed, contains('Usage: entity ${entry.value}'));
        expect(printed, isNot(contains('[arguments]')),
            reason: 'the default the args package prints when nobody '
                'declared a grammar — every verb here must have overridden it');
      });
    }
  });

  group('the refusal is derived from the same declaration', () {
    test('a call short of its arity is refused naming every positional',
        () async {
      // `show <coord> <action>` with only the coordinate typed.
      final r = await cli.run(['show', 't.chat:c1']);
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<coord> <action> are required'));
    });

    test('a single-positional verb is refused in the singular', () async {
      final r = await cli.run(['create']);
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name> is required'));
    });

    group('the `act` case that started this', () {
      test('a coordinate with no action is refused, never absorbed as the '
          "body's program name", () async {
        // The exact shape from s590: the action is omitted and the body
        // follows `--` immediately. Before the cure, `rest.length` counted
        // the body's own words and let this pass, landing an act named
        // after the body's program. `requirePositionals` reads only the
        // verb's own positionals — the body is already subtracted — so the
        // shortfall is caught before an area is even opened.
        await cli.run(['create', 't.chat', ...Cli.signed]);
        final r = await cli.run(
          ['act', 't.chat:c1', ...Cli.signed, '--', 'sh', '-c', 'echo hi'],
        );

        expect(r.code, EntityRunner.usageCode);
        expect(r.err, contains('<coord> <action> are required'));

        final log = await cli.run(['log', 't.chat:c1']);
        expect(log.out, isEmpty,
            reason: 'nothing may land on a call this surface refused');
      });
    });
  });

  group('`run` and its trailing args', () {
    test('words after `<coord> <function>` are the function\'s own, not '
        'this verb\'s arity to fail on', () async {
      await cli.run(['create', 't.chat', ...Cli.signed]);
      // `run` resolves a function the manifest declares; with none declared
      // the refusal is FunctionNotDeclared (not-found), never a usage fault
      // — proof that three-and-more words did not trip an arity check that
      // does not exist for this verb.
      final r = await cli.run(['run', 't.chat:c1', 'reindex', 'a', 'b', 'c']);
      expect(r.code, EntityRunner.notFoundCode);
      expect(r.code, isNot(EntityRunner.usageCode));
    });

    test('fewer than two positionals is still refused as usage', () async {
      final r = await cli.run(['run', 't.chat:c1']);
      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<coord> <function> are required'));
    });
  });
}
