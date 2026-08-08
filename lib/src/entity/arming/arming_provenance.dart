/// Replacement by provenance — the arming tables' new member.
///
/// **Declaration only.** The body throws [UnimplementedError]: this is the
/// design chair's contract in literal Dart, landed so the suite compiles and
/// fails naming its own missing member.
///
/// It lives beside the tables and not on the public surface because the plot's
/// layout is this component's alone, exactly as [ArmingTables] itself is: the
/// manifest-line replacement R2.4 requires is the table's member and never a
/// caller's loop.
library;

import 'dart:io';

import '../event.dart';
import 'arming.dart';

/// One line a caller asks to be armed, before an id exists for it.
///
/// A request and not a [Registration]: ids are minted where lines are written,
/// so a caller that had to supply one would be reaching into the table's own
/// business to do it.
final class Arming {
  const Arming({
    required this.instance,
    required this.pattern,
    required this.command,
    this.once = false,
  });

  final String instance;
  final EventPattern pattern;
  final List<String> command;
  final bool once;
}

extension ArmingProvenance on ArmingTables {
  /// Every line of [provenance] is removed and [declared] armed in its place —
  /// **one rewrite per table**, never a remove pass followed by an add pass.
  ///
  /// Lines of any other provenance are untouched, and their order is preserved.
  /// The returned registrations are the newly minted ones, in the order given.
  ///
  /// Idempotent by construction: applying the same [declared] twice leaves
  /// exactly one line per element, which is the whole of R4.1.
  ///
  /// Every command in [declared] passes [ArmingTables.checkCommand] before any
  /// table is rewritten; a refusal leaves every table exactly as it stood. A
  /// table holding no line of [provenance] and receiving no [declared] element
  /// for its phase is not created and not touched. The rewrite is atomic per
  /// table: a reader sees the old set of that provenance or the new one, never
  /// neither.
  List<Registration> replaceProvenance(
    Provenance provenance, {
    required Iterable<Arming> declared,
  }) {
    final requests = declared.toList();
    // Every command, before one byte is rewritten: a refusal that arrives after
    // the first table has been written is a partial write with an exception on
    // top, which is a weaker promise than the one this member makes.
    for (final request in requests) {
      ArmingTables.checkCommand(request.command);
    }

    // Read at the line and not at the registration: a table is a file people
    // edit, so a comment or a line this reader cannot decode is somebody's and
    // survives untouched, in place.
    final kept = <EventPhase, List<String>>{};
    final removed = <EventPhase, bool>{};
    for (final phase in EventPhase.values) {
      final table = tableFor(phase);
      final List<String> lines =
          table.existsSync() ? table.readAsLinesSync() : const [];
      final surviving = [
        for (final line in lines)
          if (ArmingTables.decode(line, phase)?.provenance != provenance) line,
      ];
      kept[phase] = surviving;
      removed[phase] = surviving.length != lines.length;
    }

    // Minted against what survives, so a line this rewrite is about to drop
    // does not reserve its id against the line replacing it.
    final taken = {
      for (final phase in EventPhase.values)
        for (final line in kept[phase]!) ?ArmingTables.decode(line, phase)?.id,
    };
    String mint() {
      for (var n = 1;; n++) {
        final candidate = 'r$n';
        if (taken.add(candidate)) return candidate;
      }
    }

    final minted = <Registration>[];
    for (final request in requests) {
      final armed = Registration(
        id: mint(),
        instance: request.instance,
        pattern: request.pattern,
        command: request.command,
        once: request.once,
        provenance: provenance,
      );
      minted.add(armed);
      kept[request.pattern.phase]!.add(ArmingTables.encode(armed));
    }

    for (final phase in EventPhase.values) {
      final wrote = minted.any((r) => r.pattern.phase == phase);
      // A rewrite of nothing writes nothing: an empty table is a file that did
      // not have to exist.
      if (!wrote && !removed[phase]!) continue;
      _rewrite(tableFor(phase), kept[phase]!);
    }

    return minted;
  }

  /// One table, replaced whole — written beside itself and renamed, so a reader
  /// crossing the rewrite sees the old set of lines or the new one and never
  /// neither.
  void _rewrite(File table, List<String> lines) {
    table.parent.createSync(recursive: true);
    final staged = File('${table.path}.rewriting')
      ..writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    staged.renameSync(table.path);
  }
}
