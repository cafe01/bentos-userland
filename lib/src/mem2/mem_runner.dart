import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../place/place.dart';
import 'commands/forget_command.dart';
import 'commands/recall_command.dart';
import 'commands/refocus_command.dart';
import 'commands/remember_command.dart';
import 'commands/survey_command.dart';
import 'gist_deriver.dart';
import 'mem_store.dart';
import 'model/mem_writer.dart';

/// The mem coreutil's command runner: global options (`-b/--bank`,
/// `-p/--place`), dispatch to the verb commands, and the seam that builds a
/// [MemStore] from the resolved bank and vantage place. Filesystem
/// hermeticity rides `IOOverrides` (see `runInMemoryFs`); the remaining
/// dependencies the verbs touch — clock, stdin, environment, llm — are
/// injected here.
final class MemRunner {
  MemRunner({
    StringSink? out,
    StringSink? err,
    DateTime Function()? clock,
    Map<String, String>? environment,
    GistLlm? gistLlm,
    this.stdinReader,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        clock = clock ?? DateTime.now,
        gistLlm = gistLlm ?? llmGist,
        _environment = environment ?? io.Platform.environment {
    _runner = CommandRunner<void>(
      'mem',
      "The agent's persistent memory — survey, recall, remember, refocus, forget.",
    )
      ..addCommand(SurveyCommand(this))
      ..addCommand(RecallCommand(this))
      ..addCommand(RememberCommand(this))
      ..addCommand(RefocusCommand(this))
      ..addCommand(ForgetCommand(this));

    _runner.argParser
      ..addOption('bank',
          abbr: 'b', help: r"Operate on NAME's bank (default: $BENTOS_AGENT).")
      ..addOption('place',
          abbr: 'p',
          help: 'Vantage point in the place tree — memory cascades up from here '
              '(default: current place).');
  }

  final StringSink out;
  final StringSink err;
  final DateTime Function() clock;

  /// The llm seam gist derivation pipes bodies through. Injected here so tests
  /// stub it and the write path never reaches a live model.
  final GistLlm gistLlm;

  final Map<String, String> _environment;

  /// Drains stdin when called — supplied by `bin/mem.dart` and stubbed in
  /// tests. It is a reader and not text because only `remember` without
  /// `--file` may consume stdin: draining up front would hang every verb,
  /// reads included, on an inherited pipe that never sees EOF.
  final Future<String> Function()? stdinReader;

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  /// Resolve the bank and vantage place from the global flags and build the
  /// store. Returns null (and sets exit 1) when the bank cannot be resolved.
  MemStore? buildStore(ArgResults globalResults) {
    final bank =
        (globalResults['bank'] as String?) ?? _environment['BENTOS_AGENT'];
    if (bank == null || bank.isEmpty) {
      err.writeln('mem: no bank — pass -b/--bank or set \$BENTOS_AGENT.');
      exitCode = 1;
      return null;
    }
    final placePath =
        (globalResults['place'] as String?) ?? io.Directory.current.path;
    return MemStore(
      vantage: Place(placePath),
      bank: bank,
      writer: MemWriter(clock),
    );
  }

  /// Announces the bank once, at the head of a response — the boundary that
  /// would otherwise vanish when several banks' hot bands are concatenated
  /// into one mind at wake. Called immediately before a verb's stdout output;
  /// stderr-only failures (no bank resolved, or nothing to show) skip it.
  void announceBank(String bank) {
    out.writeln('bank: $bank');
    out.writeln();
  }

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = 64;
    }
  }
}
