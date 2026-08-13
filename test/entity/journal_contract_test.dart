import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/entity.dart';
// The journal is infrastructure of one installation, like the arming tables
// beside it: it is not on the public surface, so it is proven where it lives.
import 'package:bentos_userland/src/entity/arming/arming.dart';
import 'package:bentos_userland/src/entity/journal.dart';
import 'package:test/test.dart';

/// **The dispatch journal.** JSONL in the installation's plot, in two kinds of
/// line: an occurrence written unconditionally, and a delivery written once per
/// matching subscriber.
///
/// Nothing here touches a repository. The journal is a file beside one, and a
/// suite that had to build a repository to prove a file would be asserting
/// about the wrong object.
void main() {
  late Directory scratch;
  late String gitDir;
  late Entity entity;
  late Journal journal;

  setUp(() {
    scratch = Directory(Directory.systemTemp
        .createTempSync('entity_journal')
        .resolveSymbolicLinksSync());
    gitDir = '${scratch.path}/repo.git';
    entity = Entity('bentos.llm');
    journal = Journal(gitDir, entity);
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Event event(
    String noun, {
    EventPhase phase = EventPhase.landed,
    String instance = 'demo',
    String commit = 'aaaa',
    String parent = 'bbbb',
  }) =>
      Event(
        instance: Instance(entity, instance),
        noun: noun,
        phase: phase,
        commit: Commit(commit),
        parent: Commit(parent),
      );

  OccurrenceLine occurrence(Event e, {String? sentence}) => OccurrenceLine(
        entity: 'bentos.llm',
        event: e,
        actor: const Attribution('alfred', 'alfred@test.local'),
        instant: DateTime.utc(2026, 8, 7, 16),
        sentence: sentence,
      );

  DeliveryLine delivery(
    Event e, {
    String subscriber = 'r1',
    int exitCode = 0,
    String output = '',
  }) =>
      DeliveryLine(
        entity: 'bentos.llm',
        event: e,
        subscriber: subscriber,
        command: const ['llm-runner', '--verbose'],
        exitCode: exitCode,
        output: output,
      );

  List<Map<String, Object?>> linesOf(Journal j) => [
        for (final line in j.file.readAsLinesSync())
          if (line.trim().isNotEmpty)
            jsonDecode(line) as Map<String, Object?>,
      ];

  group('where it stands', () {
    test('one file in the plot, beside the arming tables', () {
      expect(
        journal.file.path,
        '$gitDir/${ArmingTables.tablesDirName}/journal',
      );
    });

    test('appending creates the directory it needs', () {
      expect(journal.file.existsSync(), isFalse);
      journal.appendOccurrence(occurrence(event('prompt')));
      expect(journal.file.existsSync(), isTrue);
    });

    // Phase rides as a field and not as a filename. The arming tables split by
    // phase because dispatch *writes* the three differently; a reader crosses
    // phases in one call, and three files would force it to merge a time order
    // the write side never broke.
    test('all three phases land in the one file', () {
      for (final phase in EventPhase.values) {
        journal.appendOccurrence(occurrence(event('prompt', phase: phase)));
      }
      expect(linesOf(journal).map((l) => l['phase']),
          ['attempted', 'landed', 'refused']);
    });
  });

  group('two kinds of line, never one with a nullable field', () {
    test('an occurrence carries the act and who took it', () {
      journal.appendOccurrence(
        occurrence(
          event('prompt', commit: 'c0ffee', parent: 'dec0de'),
          sentence: 'alfred said prompt',
        ),
      );
      expect(linesOf(journal).single, {
        'kind': 'occurrence',
        'entity': 'bentos.llm',
        'instance': 'demo',
        'noun': 'prompt',
        'phase': 'landed',
        'commit': 'c0ffee',
        'parent': 'dec0de',
        'actor': 'alfred',
        'instant': '2026-08-07T16:00:00.000Z',
        'sentence': 'alfred said prompt',
      });
    });

    test('a sentence nobody wrote is absent, not null', () {
      journal.appendOccurrence(occurrence(event('prompt')));
      expect(linesOf(journal).single.containsKey('sentence'), isFalse);
    });

    test('a delivery carries the subscriber, the command and the answer', () {
      journal.appendDelivery(
        delivery(event('prompt'), exitCode: 3, output: 'barred — no\n'),
      );
      expect(linesOf(journal).single, {
        'kind': 'delivery',
        'entity': 'bentos.llm',
        'instance': 'demo',
        'noun': 'prompt',
        'phase': 'landed',
        'commit': 'aaaa',
        'parent': 'bbbb',
        'subscriber': 'r1',
        'command': ['llm-runner', '--verbose'],
        'exitCode': 3,
        'output': 'barred — no\n',
      });
    });

    // The whole content of *an armed body no longer fails in silence*: the
    // failure is a line with a code and its output beside it, not bytes
    // appended to an unattributed transcript.
    test('a body that failed is legible as such', () {
      journal.appendDelivery(delivery(event('prompt'), exitCode: 1, output: 'boom\n'));
      final failed = journal.deliveries({EventPattern.parse('prompt.landed')});
      expect(failed.single.exitCode, 1);
      expect(failed.single.output, 'boom\n');
    });
  });

  group('tail — the endless read', () {
    test('does not replay what was already written', () async {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));

      final stream = journal
          .tail({EventPattern.parse('prompt.landed')}, poll: _fast)
          .take(1)
          .toList();

      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));

      final seen = await stream.timeout(_patience);
      expect(seen.map((e) => e.commit.sha), ['a2']);
      expect(seen.single.instance.id, 'demo');
      expect(seen.single.instance.entity.name, 'bentos.llm');
      expect(seen.single.parent.sha, 'bbbb');
    });

    test('the pattern set selects, by noun glob and by phase', () async {
      final stream = journal.tail({
        EventPattern.parse('tool-*.landed'),
        EventPattern.parse('prompt.attempted'),
      }, poll: _fast).take(1).toList().timeout(_patience);

      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      journal.appendOccurrence(occurrence(
          event('tool-result', commit: 'a2', phase: EventPhase.attempted)));
      journal.appendOccurrence(occurrence(event('tool-result', commit: 'a3')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a4')));

      final seen = await stream;
      expect(seen.map((e) => e.commit.sha), ['a3']);
    });

    // A reader of an entity with nothing armed was promised it needed nothing
    // armed. Here that is proven structurally — the journal is read with no
    // tables directory on disk at all.
    //
    // **The seam:** the other half of the claim, that `emit` journals the
    // occurrence *before* it reads the table, is the dispatch slice's to prove.
    // This green mark says the reader does not consult the table; it says
    // nothing about the writer's order.
    test('an unarmed installation is fully visible', () async {
      final stream = journal
          .tail({EventPattern.parse('*.landed')}, poll: _fast)
          .take(1)
          .toList()
          .timeout(_patience);

      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      expect(
        Directory('$gitDir/${ArmingTables.tablesDirName}')
            .listSync()
            .map((e) => e.path.split('/').last),
        ['journal'],
      );

      final seen = await stream;
      expect(seen.single.commit.sha, 'a1');
    });

    test('deliveries are not occurrences and never surface here', () async {
      final stream = journal
          .tail({EventPattern.parse('*.landed')}, poll: _fast)
          .take(1)
          .toList()
          .timeout(_patience);

      await Future<void>.delayed(_fast * 3);
      journal.appendDelivery(delivery(event('prompt', commit: 'd1')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));

      final seen = await stream;
      expect(seen.single.commit.sha, 'a1');
    });

    test('a journal that does not exist yet is not an error', () async {
      final stream = journal
          .tail({EventPattern.parse('*.landed')}, poll: _fast)
          .take(1)
          .toList();
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      expect((await stream.timeout(_patience)).single.commit.sha, 'a1');
    });

    // Endless is the whole difference from `deliveries`, and it is what makes
    // `listen` a live view rather than a question.
    test('growth after the call is streamed', () async {
      final stream = journal
          .tail({EventPattern.parse('*.landed')}, poll: _fast)
          .take(2)
          .toList();

      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));

      expect(
        (await stream.timeout(_patience)).map((e) => e.commit.sha),
        ['a1', 'a2'],
      );
    });

    test('the stream closes with its reader and leaves nothing behind', () async {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      final sub = journal
          .tail({EventPattern.parse('*.landed')}, poll: _fast)
          .listen((_) {});
      await Future<void>.delayed(_fast * 3);
      await sub.cancel();

      // No line written, no table entry, nothing outliving the call.
      expect(
        Directory('$gitDir/${ArmingTables.tablesDirName}')
            .listSync()
            .map((e) => e.path.split('/').last),
        ['journal'],
      );
      expect(linesOf(journal).length, 1);
    });
  });

  group('since — resuming with no hole', () {
    test('streams everything after the named occurrence, exclusive', () async {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a3')));

      final seen = await journal
          .tail({EventPattern.parse('*.landed')},
              since: const Commit('a1'), poll: _fast)
          .take(2)
          .toList()
          .timeout(_patience);
      expect(seen.map((e) => e.commit.sha), ['a2', 'a3']);
    });

    // The cursor is denominated in an occurrence's own sha, and an occurrence
    // exists whether or not this reader's pattern set selects it. Scanning only
    // the matches would raise a gap for a perfectly live cursor the moment a
    // monitor narrowed its patterns between runs — the aged-out alarm firing
    // for something that never aged out, on the one channel built to tell
    // *forgotten* from *never happened*.
    test('the cursor is found even when the filter excludes it', () async {
      journal.appendOccurrence(occurrence(event('other', commit: 'a1')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));

      final seen = await journal
          .tail({EventPattern.parse('prompt.landed')},
              since: const Commit('a1'), poll: _fast)
          .take(1)
          .toList()
          .timeout(_patience);
      expect(seen.single.commit.sha, 'a2');
    });

    test('a delivery bearing the sha is not the cursor', () async {
      journal.appendDelivery(delivery(event('prompt', commit: 'a1')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));

      final seen = await journal
          .tail({EventPattern.parse('*.landed')},
              since: const Commit('a1'), poll: _fast)
          .take(1)
          .toList()
          .timeout(_patience);
      expect(seen.single.commit.sha, 'a2');
    });

    test('a cursor at the tail waits, and does not replay', () async {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      final stream = journal
          .tail({EventPattern.parse('*.landed')},
              since: const Commit('a1'), poll: _fast)
          .take(1)
          .toList();

      await Future<void>.delayed(_fast * 3);
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a2')));
      expect((await stream.timeout(_patience)).single.commit.sha, 'a2');
    });

    // A cursor the file no longer holds is a *distinct answer*, and this is the
    // seam whatever prunes later attaches to. Silently replaying from the top
    // would hand a monitor its whole history a second time; silently waiting at
    // the tail would hand it nothing and call that peace.
    test('a cursor the file does not hold raises a gap', () async {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      expect(
        journal.tail({EventPattern.parse('*.landed')},
            since: const Commit('forgotten'), poll: _fast),
        emitsError(isA<JournalGap>()
            .having((g) => g.since.sha, 'since', 'forgotten')),
      );
    });

    test('a cursor against a journal that does not exist raises a gap', () {
      expect(
        journal.tail({EventPattern.parse('*.landed')},
            since: const Commit('a1'), poll: _fast),
        emitsError(isA<JournalGap>()),
      );
    });
  });

  group('deliveries — the finite read', () {
    test('newest first, filtered by the same patterns', () {
      journal.appendDelivery(delivery(event('prompt', commit: 'a1')));
      journal.appendDelivery(
          delivery(event('tool-result', commit: 'a2'), subscriber: 'r2'));
      journal.appendDelivery(delivery(event('prompt', commit: 'a3')));

      final seen = journal.deliveries({EventPattern.parse('prompt.landed')});
      expect(seen.map((d) => d.event.commit.sha), ['a3', 'a1']);
      expect(seen.first.subscriber, 'r1');
      expect(seen.first.command, ['llm-runner', '--verbose']);
    });

    test('occurrences are not deliveries and never surface here', () {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      expect(journal.deliveries({EventPattern.parse('*.landed')}), isEmpty);
    });

    test('the limit counts what matched, and takes the newest', () {
      for (final sha in ['a1', 'a2', 'a3']) {
        journal.appendDelivery(delivery(event('prompt', commit: sha)));
        journal.appendDelivery(delivery(event('other', commit: sha)));
      }
      final seen = journal
          .deliveries({EventPattern.parse('prompt.landed')}, limit: 2);
      expect(seen.map((d) => d.event.commit.sha), ['a3', 'a2']);
    });

    test('a journal that does not exist answers nothing, not an error', () {
      expect(journal.deliveries({EventPattern.parse('*.landed')}), isEmpty);
    });

    test('the instance handle comes back whole', () {
      journal.appendDelivery(delivery(event('prompt', instance: 'other')));
      final d = journal.deliveries({EventPattern.parse('*.landed')}).single;
      expect(d.event.instance.id, 'other');
      expect(d.event.instance.entity.name, 'bentos.llm');
    });
  });

  // A reader that shrugged at a line it could not read would launder
  // corruption into normal operation, on the one channel built to be trusted.
  // The journal is allowed to fail; it is not allowed to fail quietly.
  group('a line that cannot be read raises', () {
    void poison(String line) {
      journal.appendOccurrence(occurrence(event('prompt', commit: 'a1')));
      journal.file.writeAsStringSync('$line\n', mode: FileMode.append);
    }

    test('a delivery cut in half', () {
      poison('{"kind":"delivery","entity":"bento');
      expect(() => journal.deliveries({EventPattern.parse('*.landed')}),
          throwsFormatException);
    });

    test('a line naming a kind nobody writes', () async {
      final stream = journal.tail({EventPattern.parse('*.landed')}, poll: _fast);
      final matched = expectLater(
        stream,
        emitsThrough(emitsError(isA<FormatException>())),
      );

      await Future<void>.delayed(_fast * 3);
      poison('{"kind":"rumour","instance":"demo","noun":"prompt",'
          '"phase":"landed","commit":"a2","parent":"b"}');

      await matched.timeout(_patience);
    });

    test('a line naming a phase that does not exist', () {
      poison('{"kind":"occurrence","entity":"bentos.llm","instance":"demo",'
          '"noun":"prompt","phase":"created","commit":"a2","parent":"b",'
          '"actor":"alfred","instant":"2026-08-07T16:00:00.000Z"}');
      expect(() => journal.deliveries({EventPattern.parse('*.landed')}),
          throwsFormatException);
    });

    // A trailing newline is not a fault, and a journal that raised on its own
    // last byte would be unreadable the moment it was written.
    test('a blank line is not corruption', () {
      poison('');
      expect(journal.deliveries({EventPattern.parse('*.landed')}), isEmpty);
    });
  });

  // The one law a journal may not break is lying quietly. A torn line is not a
  // degraded read the caller can shrug at: it is corruption laundered into
  // normal operation, and a reader tolerant of it would hide the fault forever.
  group('an append is atomic against another process', () {
    test('three writers, large lines, and every line survives whole', () async {
      const each = 40;
      const writers = ['w1', 'w2', 'w3'];

      final children = await Future.wait([
        for (final tag in writers)
          Process.run(
            Platform.resolvedExecutable,
            [
              'run',
              'test/entity/tools/journal_appender.dart',
              gitDir,
              tag,
              '$each',
              // Comfortably past the size at which a write stops being one
              // atomic act by luck.
              '20000',
            ],
            workingDirectory: Directory.current.path,
          ),
      ]);
      for (final child in children) {
        expect(child.exitCode, isZero, reason: '${child.stderr}');
      }

      final read = journal.deliveries({EventPattern.parse('*.landed')});
      expect(read.length, writers.length * each);
      for (final tag in writers) {
        expect(
          read.where((d) => d.subscriber == tag).map((d) => d.event.commit.sha),
          containsAll([for (var n = 0; n < each; n++) '$tag-$n']),
        );
      }
      // Every line parsed, and every one is the full length its writer wrote —
      // an interleaved append shows up here as a short line or a dead one.
      expect(read.every((d) => d.output.length == 20000), isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// The cadence the tail tests poll at. Short enough that the suite does not
/// wait on a production default, long enough to be a real poll.
const _fast = Duration(milliseconds: 5);

/// How long a test waits before calling a missing line a failure rather than a
/// slow disk.
const _patience = Duration(seconds: 5);
