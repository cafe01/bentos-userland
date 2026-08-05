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

  /// The one shape a command may not have. The table is tab-delimited and one
  /// line long, so a tab, a newline or an empty word inside an argument has no
  /// form on the wire — and a format that cannot hold a value must refuse it
  /// while the person who typed it is still at the terminal, never swallow it
  /// and fire something else later.
  static void checkCommand(List<String> command) {
    for (final word in command) {
      if (word.isEmpty) {
        throw ArgumentError.value(
          command,
          'command',
          'an empty argument cannot be armed',
        );
      }
      if (word.contains('\t') || word.contains('\n')) {
        throw ArgumentError.value(
          command,
          'command',
          'an argument cannot contain a tab or a newline (in "$word")',
        );
      }
    }
  }

  /// Appends a registration and returns it with its assigned id.
  Registration add({
    required String instance,
    required EventPattern pattern,
    required List<String> command,
    bool once = false,
  }) {
    checkCommand(command);
    final armed = Registration(
      id: _mintId(),
      instance: instance,
      pattern: pattern,
      command: command,
      once: once,
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

  /// The wire form of one line:
  /// `<id>\t<instance>\t<action>\t<lifetime>\t--\t<arg>\t<arg>…`.
  ///
  /// Tab-separated because the shim reads it with `IFS=$'\t' read`, and because
  /// a command line contains spaces and must survive being written by a
  /// program and read by a shell without either quoting the other's dialect.
  ///
  /// **The command occupies one field per argument, never one joined field.**
  /// A command is a list of words the caller already separated; joining them on
  /// a space discards that and leaves the shell to guess the boundaries back,
  /// which it does by splitting on whitespace — so an argument that contains a
  /// space arrives as two, and a quoted one arrives as neither. The delimiter
  /// the table already uses carries the boundaries the caller drew, and
  /// [checkCommand] keeps every argument expressible in it.
  ///
  /// The `--` opening the command block is what lets the two formats tell
  /// themselves apart. Without it a new line holding a single argument with a
  /// space in it reads exactly like an old line holding two arguments, and no
  /// reader — Dart or shell — could choose between them. The sentinel says
  /// *boundaries follow*, and it is the same `--` the caller typed.
  ///
  /// The lifetime stands before the command because the command is the only
  /// variadic field — and it is spelled in words rather than a flag so that a
  /// person reading the table sees what the line will do to itself.
  static String encode(Registration r) => [
        r.id,
        r.instance,
        r.pattern.action,
        r.once ? onceLifetime : alwaysLifetime,
        commandSentinel,
        ...r.command,
      ].join('\t');

  /// Opens the command block on a line written with argument boundaries kept.
  static const String commandSentinel = '--';

  static const String alwaysLifetime = 'always';
  static const String onceLifetime = 'once';

  /// Reads one line back. Returns null for a blank or commented line — a table
  /// is a file people edit, and a comment is not a fault.
  ///
  /// A line with no lifetime column is read as `always` with the whole tail as
  /// its command: tables are per installation and outlive the binary that wrote
  /// them, and an upgraded installation whose lines suddenly lost their first
  /// argument would fail silently, in the one place nothing is watching.
  ///
  /// The same debt is paid on the command itself. A tail that does not open
  /// with [commandSentinel] was written when arguments were joined on a space,
  /// and the only reading that preserves what that line has always done is to
  /// split it on whitespace — so a table armed by an older binary keeps firing
  /// exactly as it did, and only lines written from here on carry true
  /// boundaries.
  static Registration? decode(String line, EventPhase phase) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final parts = line.split('\t');
    if (parts.length < 4) return null;
    final declared = parts[3].trim();
    final stated = declared == onceLifetime || declared == alwaysLifetime;
    final fields = parts.sublist(stated ? 4 : 3);
    final kept = [
      for (final field in fields)
        if (field.trim().isNotEmpty) field.trim(),
    ];
    if (kept.isEmpty) return null;
    final List<String> command;
    if (kept.first == commandSentinel) {
      command = kept.sublist(1);
      if (command.isEmpty) return null;
    } else {
      command = kept.join(' ').split(RegExp(r'\s+'));
    }
    return Registration(
      id: parts[0],
      instance: parts[1],
      pattern: EventPattern(action: parts[2], phase: phase),
      command: command,
      once: declared == onceLifetime,
    );
  }
}
