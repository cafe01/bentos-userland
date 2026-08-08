import 'dart:io';

import 'package:bentos_userland/entity.dart';
import 'package:bentos_userland/src/entity/arming/arming.dart';

/// A child process that polls one arming table while another process rewrites
/// it, and reports the one thing an in-process assert cannot reach: whether a
/// reader **crossing the process boundary** ever saw a torn set of lines.
///
/// [ArmingProvenance.replaceProvenance]'s law is that a reader sees the old
/// set of a provenance or the new one, never neither — and its population is
/// exactly this: readers on the far side of a real process boundary, not a
/// callback inside the writer's own isolate. `_rewrite` writes beside the
/// table and renames, which is atomic on the filesystem; this is the witness
/// that the promise the mechanism relies on actually holds for a real,
/// concurrently-running reader.
///
/// Every table content the writer ever installs is a whole, self-consistent
/// declared set tagged either `a` or `b` in its last argument — never a mix —
/// so a read decoding to anything else (a line neither set contains, or lines
/// from both sets at once) is a torn read and is reported as one.
///
/// Usage: `arming_table_reader <gitDir> <sizeA> <sizeB> <durationMs>`.
void main(List<String> args) {
  final gitDir = args[0];
  final sizeA = int.parse(args[1]);
  final sizeB = int.parse(args[2]);
  final durationMs = int.parse(args[3]);

  final tables = ArmingTables(gitDir);
  final table = tables.tableFor(EventPhase.landed);
  final deadline = DateTime.now().add(Duration(milliseconds: durationMs));

  var reads = 0;
  while (DateTime.now().isBefore(deadline)) {
    if (!table.existsSync()) continue;
    final List<String> lines;
    try {
      lines = table.readAsLinesSync();
    } on FileSystemException {
      // The rename can make the path vanish for an instant between the
      // existence check and the read; that gap is not the claim under test.
      continue;
    }
    reads++;

    final tags = <String>{};
    for (final line in lines) {
      final registration = ArmingTables.decode(line, EventPhase.landed);
      if (registration == null) continue;
      tags.add(registration.command.last[0]);
    }

    if (tags.length > 1) {
      stderr.writeln('torn read: both tags present in one read — $lines');
      exit(1);
    }
    if (tags.isEmpty) continue;
    final tag = tags.single;
    final expected = tag == 'a' ? sizeA : sizeB;
    if (lines.length != expected) {
      stderr.writeln(
        'torn read: tag $tag present with ${lines.length} lines, expected '
        '$expected — $lines',
      );
      exit(1);
    }
  }

  if (reads == 0) {
    stderr.writeln('never observed a single read — the race gave the reader '
        'no chance to run');
    exit(2);
  }
  exit(0);
}
