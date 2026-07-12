/// `TtsRunner` — the coreutil's command runner.
///
/// Registers the verbs, owns `--version`, and routes a bare `tts` (with piped
/// text) to the default `synthesize` verb. Mirrors `SttRunner`; the
/// introspection verbs (`voices`, `config`) land here in a later slice.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../device.dart';
import 'synthesize_command.dart';

class TtsRunner extends CommandRunner<int> {
  TtsRunner()
      : super(
          'tts',
          'The text-to-speech coreutil — opens /dev/tts/<vendor>/<model> and '
              'streams synthesized audio.',
        ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print version and exit.',
    );
    addCommand(SynthesizeCommand());
  }

  /// [stdinHasText] is true when stdin is piped (not a TTY), so a bare
  /// `echo hi | tts` routes to `synthesize` instead of showing usage.
  @override
  Future<int> run(Iterable<String> args, {bool stdinHasText = false}) async {
    try {
      final results = parse(
        _withDefaultVerb(
          args.toList(),
          commands.keys.toSet(),
          stdinHasText: stdinHasText,
        ),
      );
      if (results['version'] == true) {
        stdout.writeln('tts $ttsVersion');
        return 0;
      }
      return await runCommand(results) ?? 0;
    } on UsageException catch (e) {
      stderr.writeln(e);
      return 64; // EX_USAGE
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command == null) {
      printUsage();
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}

/// Prepends `synthesize` when the invocation names no known verb — a bare
/// `tts` with piped text. An explicit verb or a flags-only invocation without
/// piped text is left untouched (so `--version` / `--help` still work).
List<String> _withDefaultVerb(
  List<String> args,
  Set<String> knownVerbs, {
  bool stdinHasText = false,
}) {
  final firstNonFlag = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  if (firstNonFlag.isEmpty) {
    return stdinHasText ? ['synthesize', ...args] : args;
  }
  if (knownVerbs.contains(firstNonFlag)) return args;
  return ['synthesize', ...args];
}
