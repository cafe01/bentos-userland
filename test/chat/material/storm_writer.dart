/// One writer of [the storm](storm.dart) — a whole operating-system process,
/// which is the entire point of it being a program and not a function.
///
/// It builds the channel exactly as any caller does, over the real seams, and
/// speaks under the identity it was told in argv. It counts its own attempts at
/// the act seam, because an act that lands reports no attempt count and
/// contention would otherwise be invisible on a green run.
///
///     dart run test/chat/material/storm_writer.dart \
///       --writer w0 --place /tmp/plot --channel fabrica \
///       --identity 'W0 <w0@storm.test>' --lines 8 \
///       --start-at 2026-08-12T21:00:00Z
///
/// It prints one JSON report on standard output, as its last line, whatever
/// happened — a writer that died says so, since a silent writer is a gap the
/// judge would otherwise fill in with an assumption.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bentos_userland/bentos_chat.dart';
import 'package:bentos_userland/entity.dart' show Entity;

import 'storm.dart';

Future<void> main(List<String> argv) async {
  final options = _options(argv);
  final writer = options['writer']!;
  final identity = parseStatedIdentity(options['identity']!);
  final lines = int.parse(options['lines'] ?? '8');
  final attempts = int.parse(options['attempts'] ?? '$defaultAttempts');
  final cadence = Duration(milliseconds: int.parse(options['cadence-ms'] ?? '0'));
  final payload = 'x' * int.parse(options['payload-bytes'] ?? '4096');
  final startAt = DateTime.parse(options['start-at']!).toUtc();

  final entity = Entity('bentos.chat', from: options['place']!);
  final instance = entity.instance(options['channel']!);
  final counter = _CountingActs(EntityActs(instance, identity: identity));
  Channel channelBounded(int bound) => channelConstruction(
        name: options['channel']!,
        acts: counter,
        tree: EntityTree(instance),
        identity: identity,
        ticker: () => DispatchTicker(entity),
        attempts: bound,
      );

  // **The join keeps its own bound.** `--attempts` is the knob the falsifier
  // turns, and it must turn it on the acts under judgement — the speech. A
  // single channel would apply it to the join as well, and a writer whose join
  // stumbles is then refused for every line: a red made of a cascade through
  // the setup, not of the claim. Same seams, same counter; one number differs.
  final joining = channelBounded(
    int.parse(options['join-attempts'] ?? '$defaultAttempts'),
  );
  final channel = channelBounded(attempts);

  ActRecord join;
  final said = <ActRecord>[];
  String? fault;

  try {
    // The barrier is crossed **before the join**, so joining races too: two
    // participants arriving at once is named beside simultaneous speech in the
    // requirement, and a storm that joins in the calm before it only ever
    // tests the second half.
    await _waitUntil(startAt);
    join = await _perform(counter, 'join/$writer',
        () => joining.join(displayName: writer));

    // The second barrier, where there is one: speech begins from a settled
    // roster, so the speech claims are not answered by whoever failed to get
    // in. Absent, this is the first instant again and the phases are one.
    await _waitUntil(DateTime.parse(options['speak-at'] ?? options['start-at']!).toUtc());

    for (var seq = 0; seq < lines; seq++) {
      final key = 'storm/$writer/$seq';
      said.add(await _perform(counter, key, () => channel.say('$key\n$payload')));
      if (cadence > Duration.zero) await Future<void>.delayed(cadence);
    }
  } on Object catch (error, stack) {
    fault = '$error\n$stack';
    join = ActRecord(
      key: 'join/$writer',
      outcome: ActOutcome.threw,
      startedAt: DateTime.now().toUtc(),
      endedAt: DateTime.now().toUtc(),
      attempts: 0,
      contested: 0,
      detail: '$error',
    );
  }

  stdout.writeln(jsonEncode(WriterReport(
    writer: writer,
    email: identity.handle.email,
    pid: pid,
    join: join,
    lines: said,
    fault: fault,
  ).toJson()));
  // The ticker a `wait` would have opened is never opened here, so nothing is
  // left listening; exiting explicitly keeps a stray subscription from ever
  // holding the process open and turning a finished writer into a hang.
  exit(fault == null ? 0 : 1);
}

/// Runs one act, timed, with the seam's attempt counter read across it.
Future<ActRecord> _perform(
  _CountingActs counter,
  String key,
  Future<ActResult> Function() act,
) async {
  final startedAt = DateTime.now().toUtc();
  counter.reset();
  ActResult result;
  try {
    result = await act();
  } on Object catch (error) {
    return ActRecord(
      key: key,
      outcome: ActOutcome.threw,
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
      attempts: counter.attempts,
      contested: counter.contested,
      detail: '$error',
    );
  }
  return ActRecord(
    key: key,
    outcome: switch (result) {
      Acted() => ActOutcome.acted,
      Refused() => ActOutcome.refused,
      Stumbled() => ActOutcome.stumbled,
    },
    startedAt: startedAt,
    endedAt: DateTime.now().toUtc(),
    attempts: counter.attempts,
    contested: counter.contested,
    commit: result is Acted ? result.commit : null,
    detail: switch (result) {
      Refused(:final reason) => reason,
      Stumbled(:final attempts) => 'bound $attempts',
      _ => null,
    },
  );
}

/// Sleeps in short steps rather than one long one, so a start instant already
/// past is not waited on and a clock that jumps is noticed within the step.
Future<void> _waitUntil(DateTime instant) async {
  while (DateTime.now().toUtc().isBefore(instant)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The act seam, counted. It delegates whole and decides nothing: what it adds
/// is the one number a landed act does not carry — how many times the bracket
/// was opened, and how many of those found the reference moved.
final class _CountingActs implements ChatActs {
  _CountingActs(this._inner);

  final ChatActs _inner;

  int attempts = 0;
  int contested = 0;

  void reset() {
    attempts = 0;
    contested = 0;
  }

  @override
  bool get born => _inner.born;

  @override
  void ensureBorn() => _inner.ensureBorn();

  @override
  ChatActOutcome attempt(
    String noun, {
    required void Function(ChatArea area) write,
    String? Function(ChatArea area)? gate,
    String? say,
  }) {
    attempts++;
    final outcome = _inner.attempt(noun, write: write, gate: gate, say: say);
    if (outcome is ChatContested) contested++;
    return outcome;
  }
}

Map<String, String> _options(List<String> argv) {
  final options = <String, String>{};
  for (var i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || i + 1 >= argv.length) {
      stderr.writeln('storm_writer: malformed argument ${argv[i]}');
      exit(64);
    }
    options[argv[i].substring(2)] = argv[i + 1];
  }
  for (final required in ['writer', 'place', 'channel', 'identity', 'start-at']) {
    if (!options.containsKey(required)) {
      stderr.writeln('storm_writer: --$required is required');
      exit(64);
    }
  }
  return options;
}
