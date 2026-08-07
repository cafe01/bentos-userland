import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/journal.dart';

/// A child process that appends occurrence lines to a journal through the real
/// [Journal] API, as fast as it can.
///
/// It exists because the journal's atomicity law quantifies over **processes**,
/// and a claim about concurrent processes cannot be witnessed from inside one.
/// Two isolates share a process and therefore share whatever the platform makes
/// per-process about a lock; only a second `pid` is the population the law
/// speaks about.
///
/// The `output` field is padded on purpose: a small line lands in one atomic
/// write on nearly any platform by luck, so a witness built from small lines
/// would go green over an unlocked append and prove nothing at all.
///
/// Usage: `journal_appender <gitDir> <tag> <count> <padding>`.
void main(List<String> args) {
  final gitDir = args[0];
  final tag = args[1];
  final count = int.parse(args[2]);
  final padding = int.parse(args[3]);

  final journal = Journal(gitDir, Entity('bentos.llm'));
  final filler = 'x' * padding;

  for (var n = 0; n < count; n++) {
    journal.appendDelivery(
      DeliveryLine(
        entity: 'bentos.llm',
        event: Event(
          instance: Instance(Entity('bentos.llm'), 'demo'),
          noun: 'prompt',
          phase: EventPhase.landed,
          commit: Commit('$tag-$n'),
          parent: Commit.zero,
        ),
        subscriber: tag,
        command: const ['true'],
        exitCode: 0,
        output: filler,
      ),
    );
  }
  exit(0);
}
