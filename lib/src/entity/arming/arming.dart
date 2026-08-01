import 'dart:io';

import 'package:path/path.dart' as p;

import '../event.dart';
import 'shim_source.dart';

/// The arming tables of one installation — where a [Registration] is written,
/// read and removed, and where the shim is installed.
///
/// **Arming is deployment, not entity content.** The tables live beside the
/// repository, outside every tree, and are never tracked: a cloned place
/// arrives with pins and addresses and nothing armed. That is what lets the
/// same instance run a workload at one site and only be watched at another,
/// with one line of difference between two deployments.
///
/// The layout is this component's alone. Nothing above it constructs a path
/// into `bentos/…`, exactly as no tenant constructs a path into `Place`'s
/// control plane.
final class ArmingTables {
  /// Bound to one installation's repository — the **common** directory, which
  /// the primitive resolves and no caller passes by hand.
  const ArmingTables(this.gitDir);

  final String gitDir;

  /// The directory the tables and the reactor log stand in.
  static const String tablesDirName = 'bentos';

  /// Where the shim is installed, relative to the repository.
  static const String hookPath = 'hooks/reference-transaction';

  /// The table a phase's listeners are written to. One file per phase, which is
  /// what lets the shim open exactly one and read nothing it will not use.
  File tableFor(EventPhase phase) =>
      File(p.join(gitDir, tablesDirName, phase.name));

  /// Installs the shim, mode 755, and creates the tables directory. Idempotent:
  /// arming an already-armed installation rewrites the shim and keeps the
  /// lines.
  void ensureArmed() {
    Directory(p.join(gitDir, tablesDirName)).createSync(recursive: true);
    final hook = File(p.join(gitDir, hookPath))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(referenceTransactionShim);
    // The shim is a program the substrate execs; a mode bit is the whole of
    // what makes it one.
    Process.runSync('chmod', ['755', hook.path]);
  }

  /// Appends a registration and returns it with its assigned id.
  Registration add({
    required String instance,
    required EventPattern pattern,
    required List<String> command,
  }) {
    final armed = Registration(
      id: _mintId(),
      instance: instance,
      pattern: pattern,
      command: command,
    );
    final table = tableFor(pattern.phase)..parent.createSync(recursive: true);
    table.writeAsStringSync(
      '${encode(armed)}\n',
      mode: FileMode.append,
    );
    return armed;
  }

  /// Every line armed here, across the three tables.
  List<Registration> get all => [
        for (final phase in EventPhase.values)
          for (final line in _linesOf(phase)) ?decode(line, phase),
      ];

  /// Removes the line with this id, from whichever table holds it. Idempotent.
  void remove(String id) {
    for (final phase in EventPhase.values) {
      final table = tableFor(phase);
      if (!table.existsSync()) continue;
      final kept = [
        for (final line in table.readAsLinesSync())
          if (decode(line, phase)?.id != id) line,
      ];
      table.writeAsStringSync(kept.isEmpty ? '' : '${kept.join('\n')}\n');
    }
  }

  List<String> _linesOf(EventPhase phase) {
    final table = tableFor(phase);
    return table.existsSync() ? table.readAsLinesSync() : const [];
  }

  /// A short, stable handle. Uniqueness is all it owes — the id names a line
  /// for `off` and carries no meaning of its own.
  String _mintId() {
    final taken = all.map((r) => r.id).toSet();
    for (var n = 1;; n++) {
      final candidate = 'r$n';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// The wire form of one line: `<id>\t<instance>\t<action>\t<command…>`.
  ///
  /// Tab-separated because the shim reads it with `IFS=$'\t' read`, and because
  /// a command line contains spaces and must survive being written by a
  /// program and read by a shell without either quoting the other's dialect.
  static String encode(Registration r) =>
      [r.id, r.instance, r.pattern.action, r.command.join(' ')].join('\t');

  /// Reads one line back. Returns null for a blank or commented line — a table
  /// is a file people edit, and a comment is not a fault.
  static Registration? decode(String line, EventPhase phase) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = line.split('\t');
    if (parts.length < 4) return null;
    return Registration(
      id: parts[0],
      instance: parts[1],
      pattern: EventPattern(action: parts[2], phase: phase),
      command: parts.sublist(3).join('\t').trim().split(RegExp(r'\s+')),
    );
  }
}
