import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cli_harness.dart';
import 'helpers.dart';

/// The reacting family of the coreutil: what is armed at this installation,
/// and how a stranger extends an entity it did not write.
void main() {
  late Site site;
  late Cli cli;

  setUp(() async {
    site = Site('cli');
    cli = Cli(site);
    await cli.run(['create', 't.chat', ...Cli.signed]);
    await cli.run(['new', 't.chat', 'c1']);
  });
  tearDown(() => site.dispose());

  group('entity on', () {
    test('arms a command and hands back the id off takes', () async {
      final r = await cli.run(
        ['on', 't.chat:*', 'prompt.landed', '--', 'notify.sh', '--loud'],
      );

      expect(r.code, 0);
      final id = r.out.trim();
      expect(id, isNotEmpty);

      final armed = await cli.run(['listeners', 't.chat:*']);
      // The provenance column says whose reading put the line here, and a line
      // typed at a terminal is `hand` — the mark exists so that a line an
      // installer read out of a manifest is distinguishable from this one.
      expect(
        armed.out,
        contains('$id\t*\tprompt.landed\talways\thand\tnotify.sh --loud'),
      );
    });

    test('several events, an id per line — none of them unreachable',
        () async {
      final r = await cli.run(
        ['on', 't.chat:c1', 'prompt.attempted,prompt.landed', '--', 'gate.sh'],
      );

      expect(r.code, 0);
      final ids = r.out.trim().split('\n');
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));

      for (final id in ids) {
        await cli.run(['off', 't.chat:c1', id]);
      }
      expect((await cli.run(['listeners', 't.chat:*'])).out, isEmpty);
    });

    test('the phase is what the pattern says, and both tables are read',
        () async {
      await cli.run(['on', 't.chat:*', 'prompt.attempted', '--', 'gate.sh']);
      await cli.run(['on', 't.chat:*', '*.landed', '--', 'notify.sh']);

      final r = await cli.run(['listeners', 't.chat:*']);
      expect(r.out, contains('prompt.attempted\talways\thand\tgate.sh'));
      expect(r.out, contains('*.landed\talways\thand\tnotify.sh'));
    });

    test('an unreadable pattern is never silently armed on nothing', () async {
      final r = await cli.run(['on', 't.chat:*', 'prompt.happened', '--', 'x.sh']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('unknown phase'));
      expect((await cli.run(['listeners', 't.chat:*'])).out, isEmpty);
    });

    test('without a command, it is a usage fault', () async {
      final r = await cli.run(['on', 't.chat:*', 'prompt.landed']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('-- <command>'));
    });

    test('a relative command that resolves against the place is armed',
        () async {
      File(p.join(site.root.path, 'reindex')).writeAsStringSync('#!/bin/sh\n');

      final r = await cli.run(
        ['on', 't.chat:*', 'prompt.landed', '--', './reindex'],
        cwd: site.root.path,
      );

      expect(r.code, 0, reason: 'this one does fire, and must keep arming');
      expect((await cli.run(['listeners', 't.chat:*'])).out, contains('r'));
    });

    test('a relative command armed from a subdirectory is refused, loudly',
        () async {
      // The silent failure this replaces: the line registered, the act landed,
      // and the reaction never ran — with no error at arming, none at firing,
      // and nobody left to read one. The anchor is the place, and the only
      // moment the person who typed it can be told is now.
      final sub = Directory(p.join(site.root.path, 'bin'))..createSync();
      File(p.join(sub.path, 'probe')).writeAsStringSync('#!/bin/sh\n');

      final r = await cli.run(
        ['on', 't.chat:*', 'prompt.landed', '--', './probe'],
        cwd: sub.path,
      );

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('./probe'));
      expect(r.err, contains('resolved against the place'));
      expect(
        (await cli.run(['listeners', 't.chat:*'])).out,
        isEmpty,
        reason: 'nothing that cannot fire may sit in the table looking armed',
      );
    });

    test('a bare name is left to the substrate to resolve', () async {
      // A name with no slash is PATH's business at firing time, and this
      // process's PATH is not evidence about that one — refusing here would be
      // guessing with a straight face.
      final r = await cli.run(['on', 't.chat:*', 'prompt.landed', '--', 'notify']);

      expect(r.code, 0);
    });
  });

  group('entity once', () {
    test('arms a line that says it will spend itself', () async {
      final r = await cli.run(
        ['once', 't.chat:c1', 'reply.landed', '--', 'monitor.sh'],
      );

      expect(r.code, 0);
      final armed = await cli.run(['listeners', 't.chat:c1']);
      expect(
        armed.out,
        contains('${r.out.trim()}\tc1\treply.landed\tonce\thand\tmonitor.sh'),
      );
    });

    test('it is `on` in every respect but the lifetime', () async {
      final spent = await cli.run(['once', 't.chat:*', 'reply.landed', '--', 'm.sh']);
      final standing = await cli.run(['on', 't.chat:*', 'reply.landed', '--', 'm.sh']);

      final lines = {
        for (final line in (await cli.run(['listeners', 't.chat:*'])).out.trim().split('\n'))
          line.split('\t').first: line.split('\t')[3],
      };
      expect(lines[spent.out.trim()], 'once');
      expect(lines[standing.out.trim()], 'always');
    });

    test('off takes its id like any other', () async {
      final id = (await cli.run(
        ['once', 't.chat:*', 'reply.landed', '--', 'm.sh'],
      )).out.trim();

      await cli.run(['off', 't.chat:*', id]);
      expect((await cli.run(['listeners', 't.chat:*'])).out, isEmpty);
    });

    test('an unreadable pattern is never silently armed on nothing', () async {
      final r = await cli.run(['once', 't.chat:*', 'reply.happened', '--', 'm.sh']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('unknown phase'));
      expect((await cli.run(['listeners', 't.chat:*'])).out, isEmpty);
    });

    test('without a command, it is a usage fault', () async {
      final r = await cli.run(['once', 't.chat:*', 'reply.landed']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('-- <command>'));
    });
  });

  group('entity listeners', () {
    test('an instance sees what is armed for it and what is armed for all',
        () async {
      await cli.run(['on', 't.chat:c1', 'prompt.landed', '--', 'mine.sh']);
      await cli.run(['on', 't.chat:c2', 'prompt.landed', '--', 'theirs.sh']);
      await cli.run(['on', 't.chat:*', 'prompt.landed', '--', 'everyones.sh']);

      final r = await cli.run(['listeners', 't.chat:c1']);
      expect(r.out, contains('mine.sh'));
      expect(r.out, contains('everyones.sh'));
      expect(r.out, isNot(contains('theirs.sh')));
    });

    test('nothing armed is silence, not a failure', () async {
      final r = await cli.run(['listeners', 't.chat:*']);

      expect(r.code, 0);
      expect(r.out, isEmpty);
    });

    test('arming is per installation — a second copy is a participant',
        () async {
      // Two installations of one entity are two participants, not two views,
      // and treating them as views is what quietly destroys differentiated
      // arming.
      final elsewhere = Site('elsewhere');
      addTearDown(elsewhere.dispose);
      final there = Cli(elsewhere, git: site.git);
      await there.run(['install', repositoryOf(site.root.path, 't.chat')]);

      await cli.run(['on', 't.chat:*', 'prompt.landed', '--', 'here.sh']);

      expect((await there.run(['listeners', 't.chat:*'])).out, isEmpty);
      expect((await cli.run(['listeners', 't.chat:*'])).out, contains('here.sh'));
    });
  });

  group('entity off', () {
    test('is idempotent — a caller that crashed may honestly run it twice',
        () async {
      final id = (await cli.run(
        ['on', 't.chat:*', 'prompt.landed', '--', 'notify.sh'],
      )).out.trim();

      expect((await cli.run(['off', 't.chat:*', id])).code, 0);
      expect((await cli.run(['off', 't.chat:*', id])).code, 0);
      expect((await cli.run(['listeners', 't.chat:*'])).out, isEmpty);
    });

    test('without an id, it is a usage fault', () async {
      final r = await cli.run(['off', 't.chat:*']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<id>'));
    });
  });

  group('entity listen and entity deliveries — vocabulary', () {
    // Blocking against a real journal, resuming past a cursor, a killed
    // process leaving nothing behind — all real-substrate claims, proven in
    // `subscribing_contract_test.dart`. What is checkable here, cheaply and
    // without ever opening the stream, is arity and pattern grammar.

    test('listen without an event is a usage fault', () async {
      final r = await cli.run(['listen', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name> <event[,event]>'));
    });

    test('listen on an unreadable pattern is never silently opened', () async {
      final r = await cli.run(['listen', 't.chat', 'prompt.happened']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('unknown phase'));
    });

    test('deliveries without an event is a usage fault', () async {
      final r = await cli.run(['deliveries', 't.chat']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('<name> <event[,event]>'));
    });

    test('deliveries on an unreadable pattern is never silently answered',
        () async {
      final r = await cli.run(['deliveries', 't.chat', 'prompt.happened']);

      expect(r.code, EntityRunner.usageCode);
      expect(r.err, contains('unknown phase'));
    });

    test('deliveries on an entity nobody armed is silence, not a failure',
        () async {
      final r = await cli.run(['deliveries', 't.chat', '*.landed']);

      expect(r.code, 0);
      expect(r.out, isEmpty);
    });
  });
}
