/// The floor, for real: `entity` on the PATH, one process per verb.
///
/// This is the only file in the layer that knows a process exists. Everything
/// above it is judged with no process at all, which is why the contract suite
/// runs in milliseconds and why the seam this file covers is the one the
/// material gate exists for.
library;

import 'dart:io';

import 'coordinate.dart';
import 'primitive.dart';

/// The primitive's own grade for a **verdict**: a gate said no, and the same
/// act will be barred again. Named because it is the floor's and not ours —
/// re-exported here because the CLI layer already reaches for it by this
/// name; [contestedCode] lives in `primitive.dart`, which this face's own
/// callers reach instead.
const int refusedCode = 3;

final class EntityPrimitive implements Primitive {
  const EntityPrimitive({this.executable = 'entity'});

  final String executable;

  @override
  Future<Sha?> tip(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final result = await _entity(['tip', _spell(coord)], vantage);
    // Not born is an answer, not a failure: it is what `show` turns into *this
    // conversation has not been opened*.
    if (result.exitCode != 0) return null;
    final sha = result.stdout.trim();
    return sha.isEmpty ? null : Sha(sha);
  }

  @override
  Future<List<InstanceRef>> instances(
    String entity, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final result = await _demand(['ls', entity], vantage, 'ls');
    return [
      for (final line in _lines(result.stdout))
        if (line.split('\t') case [final instance, ...final rest])
          InstanceRef(
            instance,
            rest.isEmpty || rest.first.trim().isEmpty
                ? null
                : Sha(rest.first.trim()),
          ),
    ];
  }

  @override
  Future<List<String>> ls(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    final result = await _demand(
      ['ls', '${_spell(coord)}:$path', ..._asOf(asOf)],
      vantage,
      'ls',
    );
    return _lines(result.stdout);
  }

  @override
  Future<String> read(
    Coordinate coord,
    String path, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    final result = await _demand(
      ['read', '${_spell(coord)}:$path', ..._asOf(asOf)],
      vantage,
      'read',
    );
    return result.stdout as String;
  }

  @override
  Future<List<Act>> log(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final result = await _demand(['log', _spell(coord)], vantage, 'log');
    final acts = <Act>[];
    for (final line in _lines(result.stdout)) {
      final fields = line.split('\t');
      if (fields.length < 4) continue;
      // A commit carrying no noun is not an act — it is one of the commits that
      // authored the entity itself, which the primitive's log walks into. That
      // it does is a finding against `entity log`; dropping them here is what
      // keeps a conversation's history the conversation's.
      if (fields[1].trim().isEmpty) continue;
      final instant = DateTime.tryParse(fields[3]);
      if (instant == null) continue;
      final sentence = fields.length > 4 ? fields[4] : '';
      acts.add(Act(
        sha: Sha(fields[0]),
        name: fields[1],
        actor: fields[2],
        instant: instant,
        sentence: sentence.isEmpty ? null : sentence,
      ));
    }
    // The primitive hands the log back newest first; the face reads a history.
    return acts.reversed.toList();
  }

  @override
  Future<Sha> birth(
    Coordinate coord, {
    Sha? from,
    Vantage vantage = const Vantage.here(),
  }) async {
    await _demand(
      [
        'new',
        coord.entity,
        coord.instance,
        if (from != null) ...['--from', from.value],
      ],
      vantage,
      'new',
    );
    final born = await tip(coord, vantage: vantage);
    if (born == null) {
      throw const PrimitiveFailure('new', 'the instance was not born');
    }
    return born;
  }

  @override
  Future<RunOutcome> run(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  }) async {
    // Every exit code comes back as a value, unread here: 3 [refusedCode] is
    // a verdict and 4 [contestedCode] is a stumble, and telling them apart is
    // the caller's job, not this floor's. The caller reads the floor's own
    // words off stderr. Only a process that could not run at all is a
    // failure of ours.
    final result = await _entity(
      ['run', _spell(coord), function, if (arguments.isNotEmpty) ...['--', ...arguments]],
      vantage,
    );
    return RunOutcome(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  @override
  Future<int> attach(
    Coordinate coord,
    String function,
    List<String> arguments, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final process = await Process.start(
      executable,
      [
        ..._place(vantage),
        'run',
        _spell(coord),
        function,
        if (arguments.isNotEmpty) ...['--', ...arguments],
      ],
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  // ── the process ──────────────────────────────────────────────────────────

  String _spell(Coordinate coord) => '${coord.entity}:${coord.instance}';

  List<String> _place(Vantage vantage) =>
      vantage.place == null ? const [] : ['-C', vantage.place!];

  List<String> _asOf(Sha? asOf) =>
      asOf == null ? const [] : ['--as-of', asOf.value];

  Future<ProcessResult> _entity(List<String> arguments, Vantage vantage) async {
    try {
      return await Process.run(executable, [..._place(vantage), ...arguments]);
    } on ProcessException catch (e) {
      // The primitive is not on the PATH, or could not be started. That is not
      // a refusal and must never read as one.
      throw PrimitiveFailure(arguments.first, e.message);
    }
  }

  Future<ProcessResult> _demand(
    List<String> arguments,
    Vantage vantage,
    String verb,
  ) async {
    final result = await _entity(arguments, vantage);
    if (result.exitCode != 0) {
      throw PrimitiveFailure(
        verb,
        (result.stderr as String).trim(),
        exitCode: result.exitCode,
      );
    }
    return result;
  }

  List<String> _lines(Object? stdout) => (stdout as String)
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.isNotEmpty)
      .toList();
}
