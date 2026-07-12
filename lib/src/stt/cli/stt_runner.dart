/// `SttRunner` — the coreutil's command runner.
///
/// Registers the verbs, owns `--version`, and routes a bare `stt` (with piped
/// audio) to the default `transcribe` verb. Mirrors `LlmRunner`.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../device.dart';
import 'live_command.dart';
import 'transcribe_command.dart';

class SttRunner extends CommandRunner<int> {
  SttRunner()
      : super(
          'stt',
          'The speech-to-text coreutil — opens /dev/stt/<vendor>/<model>/<verb> '
              'and streams the transcript.',
        ) {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print version and exit.',
    );
    addCommand(TranscribeCommand());
    addCommand(LiveCommand());
  }

  /// [stdinHasAudio] is true when stdin is piped (not a TTY), so a bare
  /// `cat audio.wav | stt` routes to `transcribe` instead of showing usage.
  @override
  Future<int> run(Iterable<String> args, {bool stdinHasAudio = false}) async {
    try {
      final results = parse(
        _withDefaultVerb(
          args.toList(),
          commands.keys.toSet(),
          stdinHasAudio: stdinHasAudio,
        ),
      );
      if (results['version'] == true) {
        stdout.writeln('stt $sttVersion');
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

/// Prepends `transcribe` when the invocation names no known verb — a bare
/// `stt` with piped audio, or `stt -l pt`. An explicit verb or a flags-only
/// invocation without piped audio is left untouched (so `--version` / `--help`
/// still work).
List<String> _withDefaultVerb(
  List<String> args,
  Set<String> knownVerbs, {
  bool stdinHasAudio = false,
}) {
  final firstNonFlag = args.firstWhere(
    (a) => !a.startsWith('-'),
    orElse: () => '',
  );
  if (firstNonFlag.isEmpty) {
    return stdinHasAudio ? ['transcribe', ...args] : args;
  }
  if (knownVerbs.contains(firstNonFlag)) return args;
  return ['transcribe', ...args];
}
