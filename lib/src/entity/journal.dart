import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../git/model/actor.dart';
import '../git/model/commit.dart';
import 'arming/arming.dart';
import 'entity.dart';
import 'event.dart';
import 'instance.dart';

/// One occurrence, written unconditionally the moment `Entity.emit` journals it
/// — before the arming tables are even read. What [Journal.tail] reads, and the
/// whole of what a `listen` reader ever sees.
final class OccurrenceLine {
  const OccurrenceLine({
    required this.entity,
    required this.event,
    required this.actor,
    required this.instant,
    this.sentence,
  });

  /// The installation's own name — `BENTOS_ENTITY`.
  final String entity;
  final Event event;

  /// Who acted, from the commit's author — **null when the commit could not be
  /// read at all**, which at `.landed` is journaled rather than refused.
  ///
  /// Absent, and never a stand-in name: an invented author is the defect this
  /// system already paid for once, and *nobody knows* is a different fact from
  /// *somebody called unknown*.
  final Actor? actor;

  final DateTime instant;

  /// The act's legible sentence, stored and never interpreted.
  final String? sentence;

  Map<String, Object?> toJson() => {
        'kind': Journal.occurrenceKind,
        'entity': entity,
        'instance': event.instance.id,
        'noun': event.noun,
        'phase': event.phase.suffix,
        'commit': event.commit.sha,
        'parent': event.parent.sha,
        if (actor != null) 'actor': actor!.name,
        'instant': instant.toIso8601String(),
        if (sentence != null) 'sentence': sentence,
      };
}

/// One occurrence crossed with one matching `Registration` — written once
/// dispatch has resolved a match, never for a registration that did not match
/// and never for an occurrence nobody was armed on.
///
/// `reactor.log`'s replacement: the same bytes, addressed to the line that
/// produced them instead of appended to an unattributed transcript.
final class DeliveryLine {
  const DeliveryLine({
    required this.entity,
    required this.event,
    required this.subscriber,
    required this.command,
    required this.exitCode,
    required this.output,
  });

  final String entity;
  final Event event;

  /// The `Registration.id` that matched.
  final String subscriber;
  final List<String> command;

  /// The woken body's own exit code, carried and never reinterpreted — the same
  /// posture `run` already holds toward a body it executes.
  final int exitCode;

  /// Combined stdout and stderr, captured whole.
  final String output;

  Map<String, Object?> toJson() => {
        'kind': Journal.deliveryKind,
        'entity': entity,
        'instance': event.instance.id,
        'noun': event.noun,
        'phase': event.phase.suffix,
        'commit': event.commit.sha,
        'parent': event.parent.sha,
        'subscriber': subscriber,
        'command': command,
        'exitCode': exitCode,
        'output': output,
      };
}

/// A [Journal.tail] `since` cursor named a commit the file no longer holds —
/// the seam retention attaches to, whenever it exists.
///
/// Distinct from an occurrence that never happened: this one happened and was
/// forgotten. Nothing prunes the journal today, so the only way to see this is
/// a cursor that was never in this file at all — or a file that shrank under a
/// reader, which is the same fact arriving early.
final class JournalGap implements Exception {
  const JournalGap(this.since);
  final Commit since;

  @override
  String toString() => 'JournalGap: no occurrence ${since.short} in the journal';
}

/// The journal of one installation — the mechanism of dispatch, not its log.
///
/// JSONL, append-only, in **two kinds of line**: an occurrence, written once
/// per occurrence whatever the tables say, and a delivery, written once per
/// matching subscriber. A reader of one never reads a field the other needed,
/// and an unarmed installation is fully visible to `listen` because occurrences
/// do not wait on a table to exist.
///
/// > **Appends are atomic against concurrent processes**, and callers rely on
/// > it. Every append takes an exclusive lock on the file and writes one whole
/// > line; readers additionally hold back a trailing partial line until its
/// > newline arrives, so a torn read is impossible in either direction. What a
/// > reader will never do is *tolerate* a broken line: a malformed line raises,
/// > because the one thing a journal may not do is lie quietly.
///
/// Retention has no owner. The file grows with every act, forever, and nothing
/// here prunes it — what this component owes meanwhile is that a cursor which
/// has aged out is a distinct answer ([JournalGap]) and never silence.
final class Journal {
  /// The journal of the installation whose repository is [gitDir], belonging to
  /// [entity].
  ///
  /// **Both, because a journal is of one installation** — and an installation
  /// is an entity anchored in a place. A read hands back an [Event] carrying an
  /// [Instance] handle, and a bare id would make every consumer re-derive what
  /// this object already knows. The handle costs nothing: [Instance] is lazy,
  /// so reconstruction touches no disk.
  const Journal(this.gitDir, this.entity);

  final String gitDir;
  final Entity entity;

  static const String fileName = 'journal';

  static const String occurrenceKind = 'occurrence';
  static const String deliveryKind = 'delivery';

  /// How often a [tail] with no news looks again.
  ///
  /// A poll of the file's length is one `stat`, so ten a second costs nothing
  /// measurable — and 100ms is under the threshold at which a person reading a
  /// live transcript perceives lag, which is the demanding half of the audience.
  /// A machine reader wants the opposite trade and can say so: the argument
  /// exists precisely because a human-facing tail and a batch consumer do not
  /// want one number.
  static const Duration defaultPoll = Duration(milliseconds: 100);

  File get file =>
      File(p.join(gitDir, ArmingTables.tablesDirName, fileName));

  void appendOccurrence(OccurrenceLine line) => _append(line.toJson());

  void appendDelivery(DeliveryLine line) => _append(line.toJson());

  /// Occurrences matching [events], streamed as they are appended by any
  /// process, forever — the call does not return until the caller stops reading
  /// it. Nothing about the reader is written down: no line, no table entry,
  /// nothing outliving the call, which is the whole property `listen` exists to
  /// have.
  ///
  /// With no [since], starts at the top of the file. With one, scans forward
  /// for the occurrence whose commit equals it and streams everything
  /// **after** — a full-file scan, stated as the cost rather than hidden behind
  /// an offset or a timestamp that would not survive a rewrite. **The scan runs
  /// over every occurrence, not only the matching ones**: the cursor is
  /// denominated in an occurrence's own sha, and an occurrence exists whether or
  /// not this reader's patterns select it. Reaches the end having never found
  /// it: raises [JournalGap], never silently falls back to the top or the tail.
  ///
  /// Growth is read by polling the file's length on the reader's own [poll]
  /// cadence — which is what lets [file] stay an ordinary file with no socket,
  /// no registered lifetime, and nothing a crashed reader leaves behind.
  Stream<Event> tail(
    Set<EventPattern> events, {
    Commit? since,
    Duration poll = defaultPoll,
  }) {
    // A controller and not an `async*` body, for one reason: a generator
    // observes cancellation only when it reaches a `yield`, so a cancelled
    // reader on a quiet journal would go on polling forever with nobody left to
    // hear it. The flag is checked at the top of the loop, so the poll stops
    // with the reader — *nothing outliving the call* is the property, and it
    // has to be true of the poll and not only of the file.
    final controller = StreamController<Event>();
    var live = true;
    controller.onCancel = () => live = false;
    controller.onListen = () => _pump(controller, events, since, poll, () => live);
    return controller.stream;
  }

  Future<void> _pump(
    StreamController<Event> controller,
    Set<EventPattern> events,
    Commit? since,
    Duration poll,
    bool Function() live,
  ) async {
    var remainder = '';
    var last = since;
    try {
      var consumed = since == null ? 0 : _scanForCursor(since);
      while (live()) {
        final length = file.existsSync() ? file.lengthSync() : 0;

        // The file lost bytes a reader had already been promised. Nothing
        // prunes today, so this is retention arriving before its owner did —
        // the same fact [JournalGap] names, not a shorter file to carry on
        // with.
        if (length < consumed) throw JournalGap(last ?? Commit.zero);

        if (length > consumed) {
          remainder += _readFrom(consumed, length - consumed);
          consumed = length;
          // A line is held back until its newline arrives: an append is atomic
          // against other writers, and this is the reader's half of the same
          // guarantee — never seeing one mid-flight.
          final parts = remainder.split('\n');
          remainder = parts.removeLast();
          for (final line in parts) {
            final entry = _parse(line);
            if (entry is! OccurrenceLine) continue;
            last = entry.event.commit;
            if (_matches(entry.event, events)) controller.add(entry.event);
          }
        }

        await Future<void>.delayed(poll);
      }
    } catch (error, trace) {
      if (live()) controller.addError(error, trace);
    } finally {
      await controller.close();
    }
  }

  /// What the hooks did — the second consumer, and the reason this file
  /// replaces `reactor.log` rather than sitting beside it. A finite read of the
  /// deliveries recorded for [events], newest first, since the question it
  /// answers is *what happened to the act I just took* and not *what is
  /// happening now*.
  ///
  /// An armed body that failed is a line with a non-zero [DeliveryLine.exitCode]
  /// and its output beside it, which is the entire content of *an armed body no
  /// longer fails in silence*.
  List<DeliveryLine> deliveries(Set<EventPattern> events, {int? limit}) {
    if (!file.existsSync()) return const [];
    final found = <DeliveryLine>[];
    for (final line in file.readAsLinesSync().reversed) {
      final entry = _parse(line);
      if (entry is! DeliveryLine) continue;
      if (!_matches(entry.event, events)) continue;
      found.add(entry);
      if (limit != null && found.length >= limit) break;
    }
    return found;
  }

  /// The byte offset just past the line naming [since]. Throws [JournalGap]
  /// when the file, as it stands, does not hold it.
  int _scanForCursor(Commit since) {
    if (!file.existsSync()) throw JournalGap(since);
    final bytes = file.readAsBytesSync();
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0a) continue;
      final entry = _parse(utf8.decode(bytes.sublist(start, i)));
      start = i + 1;
      // Every occurrence is scanned, not only the ones [tail] will emit: a
      // reader that narrowed its patterns between runs still holds a live
      // cursor, and a filtered scan would answer it with a gap.
      if (entry is OccurrenceLine && entry.event.commit == since) return start;
    }
    throw JournalGap(since);
  }

  String _readFrom(int offset, int count) {
    final handle = file.openSync();
    try {
      handle.setPositionSync(offset);
      return utf8.decode(handle.readSync(count));
    } finally {
      handle.closeSync();
    }
  }

  void _append(Map<String, Object?> json) {
    file.parent.createSync(recursive: true);
    final handle = file.openSync(mode: FileMode.append);
    try {
      handle.lockSync(FileLock.blockingExclusive);
      // **After the lock, and not before.** Opening for append fixes the write
      // position at the length the file had *then*; two writers that opened
      // before either wrote hold the same stale offset and land on top of one
      // another. Re-seeking under the lock is what makes the offset true.
      handle.setPositionSync(handle.lengthSync());
      handle.writeFromSync(utf8.encode('${jsonEncode(json)}\n'));
      handle.flushSync();
    } finally {
      handle.unlockSync();
      handle.closeSync();
    }
  }

  bool _matches(Event event, Set<EventPattern> events) => events.any(
        (p) => p.phase == event.phase && p.matchesAction(event.noun),
      );

  /// One line back as the kind it was written as. Null for a blank line — a
  /// trailing newline is not a fault. Anything else raises: a line that cannot
  /// be read is corruption, and swallowing it would launder corruption into
  /// normal operation on the one channel built to be trusted.
  Object? _parse(String line) {
    if (line.trim().isEmpty) return null;
    final Map<String, Object?> json;
    try {
      json = jsonDecode(line) as Map<String, Object?>;
    } on Object {
      throw FormatException('unreadable journal line', line);
    }

    final event = Event(
      instance: Instance(entity, json['instance']! as String),
      noun: json['noun']! as String,
      phase: EventPhase.values.firstWhere(
        (p) => p.suffix == json['phase'],
        orElse: () =>
            throw FormatException('unknown phase: ${json['phase']}', line),
      ),
      commit: Commit(json['commit']! as String),
      parent: Commit(json['parent']! as String),
    );

    switch (json['kind']) {
      case occurrenceKind:
        return OccurrenceLine(
          entity: json['entity']! as String,
          event: event,
          actor: switch (json['actor']) {
            final String named => Actor(named),
            _ => null,
          },
          instant: DateTime.parse(json['instant']! as String),
          sentence: json['sentence'] as String?,
        );
      case deliveryKind:
        return DeliveryLine(
          entity: json['entity']! as String,
          event: event,
          subscriber: json['subscriber']! as String,
          command: [
            for (final word in json['command']! as List) word as String,
          ],
          exitCode: json['exitCode']! as int,
          output: json['output']! as String,
        );
      default:
        throw FormatException('unknown journal line kind: ${json['kind']}', line);
    }
  }
}
