/// `TtsRunner` — the coreutil's command runner.
///
/// Registers the verbs, owns `--version`, and routes a bare `tts` (piped
/// text, a positional argument, or an interactive terminal, §5.4-3/product-
/// spec fork #10) to the default `synthesize` verb. Mirrors `SttRunner`; the
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

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(withDefaultVerb(args.toList(), commands.keys.toSet()));
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

/// Prepends `synthesize` when the invocation names no known verb — every
/// bare `tts` invocation resolves to the default verb (§4.2: "a bare `tts`
/// at a terminal thus resolves to the default verb reading the keyboard,
/// never a usage dump"). `--version`/`--help` are the sole exceptions, so
/// they still short-circuit before a command ever runs.
List<String> withDefaultVerb(List<String> args, Set<String> knownVerbs) {
  if (args.contains('--version') || args.contains('-h') || args.contains('--help')) {
    return args;
  }
  final firstNonFlag = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  if (firstNonFlag.isEmpty) return ['synthesize', ...args];
  if (knownVerbs.contains(firstNonFlag)) return args;
  return ['synthesize', ...args];
}
