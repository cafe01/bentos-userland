import 'package:bentos_userland/entity.dart';
// The table's layout is that component's alone and stays out of the public
// surface, so the wire form is proven where it lives.
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// **Tier A — arming.** What `on` writes, where it writes it, and the laws that
/// make one entity behave differently at two sites.
///
/// The design code in the vocabulary itself — parsing a pattern, matching a
/// glob, encoding a line — is green today; it is design's own, not
/// construction's.
void main() {
  group('the event vocabulary (design code — green today)', () {
    test('a pattern is an action and a phase', () {
      final p = EventPattern.parse('prompt.landed');
      expect(p.action, 'prompt');
      expect(p.phase, EventPhase.landed);
      expect(p.toString(), 'prompt.landed');
    });

    test('the three phases, and nothing else, are readable', () {
      expect(EventPattern.parse('x.attempted').phase, EventPhase.attempted);
      expect(EventPattern.parse('x.refused').phase, EventPhase.refused);
      expect(() => EventPattern.parse('x.created'), throwsFormatException);
      expect(() => EventPattern.parse('prompt'), throwsFormatException);
    });

    test('a hyphenated noun keeps its hyphens', () {
      expect(EventPattern.parse('tool-result.landed').action, 'tool-result');
    });

    test('globs select over action names', () {
      expect(EventPattern.parse('*.landed').matchesAction('prompt'), isTrue);
      expect(EventPattern.parse('tool-*.landed').matchesAction('tool-result'), isTrue);
      expect(EventPattern.parse('tool-*.landed').matchesAction('prompt'), isFalse);
      expect(EventPattern.parse('prompt.landed').matchesAction('prompt-2'), isFalse);
    });
  });

  group('arming (contract — red until construction)', () {
    late Site site;
    late Entity llm;

    setUp(() {
      site = Site();
      site.run(() => llm = Entity('bentos.llm', from: site.root.path).create());
    });
    tearDown(() => site.dispose());

    test('a registration is a command line, and comes back listed', () {
      site.run(() {
        final r = llm.on(
          {EventPattern.parse('prompt.landed')},
          command: ['llm-runner', '--verbose'],
        );
        expect(r.command, ['llm-runner', '--verbose']);
        expect(llm.listeners.map((l) => l.id), contains(r.id));
      });
    });

    test('one call over several patterns arms each of them', () {
      site.run(() {
        llm.on(
          {EventPattern.parse('prompt.landed'), EventPattern.parse('prompt.attempted')},
          command: ['llm-runner'],
        );
        expect(
          llm.listeners.map((l) => l.pattern.phase).toSet(),
          {EventPhase.landed, EventPhase.attempted},
        );
      });
    });

    test('off is idempotent', () {
      site.run(() {
        final r = llm.on({EventPattern.parse('prompt.landed')}, command: ['x']);
        llm.off(r.id);
        llm.off(r.id);
        expect(llm.listeners, isEmpty);
      });
    });

    test('arming is per installation — one site runs, another only watches', () {
      final downstream = site.nested('downstream');
      site.run(() {
        final there = Entity('bentos.llm', from: downstream.path).create();
        there.on({EventPattern.parse('prompt.landed')}, command: ['llm-runner']);

        expect(there.listeners, hasLength(1));
        expect(
          Entity('bentos.llm', from: site.root.path).listeners,
          isEmpty,
          reason: 'what differs between two deployments is one line in a table',
        );
      });
    });

    test('an instance selector defaults to every instance', () {
      site.run(() {
        final r = llm.on({EventPattern.parse('prompt.landed')}, command: ['x']);
        expect(r.instance, '*');
      });
    });

    test('a line armed by `once` says so, and one armed by `on` does not', () {
      site.run(() {
        final spent = llm.once({EventPattern.parse('reply.landed')}, command: ['m']);
        final standing = llm.on({EventPattern.parse('prompt.landed')}, command: ['r']);
        expect(spent.once, isTrue);
        expect(standing.once, isFalse);
        // Round trip: the lifetime is what the table carries, not what the
        // handle remembers — the shim reads the file and nothing else.
        final read = {for (final l in llm.listeners) l.id: l.once};
        expect(read[spent.id], isTrue);
        expect(read[standing.id], isFalse);
      });
    });
  });

  group('the wire form of a line', () {
    Registration line(String encoded) =>
        ArmingTables.decode(encoded, EventPhase.landed)!;

    test('round trips through the table, lifetime and all', () {
      const armed = Registration(
        id: 'r7',
        instance: 's1',
        pattern: EventPattern(action: 'prompt', phase: EventPhase.landed),
        command: ['llm-runner', '--at', '/tmp/ent'],
        once: true,
      );
      final read = line(ArmingTables.encode(armed));
      expect(read.id, 'r7');
      expect(read.instance, 's1');
      expect(read.pattern.action, 'prompt');
      expect(read.command, ['llm-runner', '--at', '/tmp/ent']);
      expect(read.once, isTrue);
    });

    test('a line written before the lifetime existed keeps its whole command', () {
      // Tables are per installation and outlive the binary that wrote them. Read
      // the old shape by the new rule and the command silently loses its first
      // argument — in the one place nobody is watching.
      final read = line(['r1', '*', 'prompt', 'llm-runner --at /tmp/ent'].join('\t'));
      expect(read.command, ['llm-runner', '--at', '/tmp/ent']);
      expect(read.once, isFalse);
    });

    test('a command whose first word is a lifetime word is still the command', () {
      final read = line(['r1', '*', 'prompt', 'always', 'once --now'].join('\t'));
      expect(read.command, ['once', '--now']);
      expect(read.once, isFalse);
    });

    test('a blank, a comment and a line with no command are not lines', () {
      expect(ArmingTables.decode('', EventPhase.landed), isNull);
      expect(ArmingTables.decode('# off for now', EventPhase.landed), isNull);
      expect(
        ArmingTables.decode(['r1', '*', 'prompt', 'once', ''].join('\t'),
            EventPhase.landed),
        isNull,
        reason: 'a registration with nothing to wake is not a registration',
      );
    });
  });
}
