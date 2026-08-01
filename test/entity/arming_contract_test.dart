import 'package:bentos_userland/entity.dart';
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
  });
}
