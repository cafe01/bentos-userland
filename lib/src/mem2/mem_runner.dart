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

/// The mem coreutil's command runner: global options (`-a/--agent`,
/// `-p/--place`), dispatch to the verb commands, and the seam that builds a
/// [MemStore] from the resolved agent and vantage place. Filesystem
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
    this.stdinContent,
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
      ..addOption('agent',
          abbr: 'a', help: r"Operate on NAME's memory (default: $BENTOS_AGENT).")
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

  /// Pre-canned stdin for hermetic tests; null = real stdin.
  final String? stdinContent;

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  /// Resolve the agent and vantage place from the global flags and build the
  /// store. Returns null (and sets exit 1) when the agent cannot be resolved.
  MemStore? buildStore(ArgResults globalResults) {
    final agent =
        (globalResults['agent'] as String?) ?? _environment['BENTOS_AGENT'];
    if (agent == null || agent.isEmpty) {
      err.writeln('mem: no agent — pass -a/--agent or set \$BENTOS_AGENT.');
      exitCode = 1;
      return null;
    }
    final placePath =
        (globalResults['place'] as String?) ?? io.Directory.current.path;
    return MemStore(
      vantage: Place(placePath),
      entity: agent,
      writer: MemWriter(clock),
    );
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
