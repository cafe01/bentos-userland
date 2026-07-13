/// `tts synthesize` (the default, nameless-in-use verb) — bounded text on
/// stdin to an audio stream on stdout.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_driver_sdk/bentos_driver_sdk.dart' show DriverError;
import 'package:tts_inference/tts_inference.dart';

import '../../../boot_tts.dart';
import '../device.dart';
import '../feedback.dart';
import '../sink.dart';
import '../synthesize.dart';
import '../text_source.dart';
import '../wav_length_patch.dart';

class SynthesizeCommand extends Command<int> {
  SynthesizeCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device /dev/tts/<vendor>/<model> '
            '(overrides $ttsDeviceEnvVar and the default).',
      )
      ..addOption(
        'voice',
        help: 'Voice id (see `tts voices`). Omit for the provider default.',
        valueHelp: 'id',
      )
      ..addOption(
        'speed',
        abbr: 's',
        help: 'Speech-rate multiplier. Omit for the provider default.',
        valueHelp: 'x',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['wav', 'pcm'],
        defaultsTo: 'wav',
        help: 'Output format. wav (default) is self-describing; pcm is '
            'headerless raw audio and requires --rate.',
      )
      ..addOption(
        'rate',
        abbr: 'r',
        help: 'PCM sample rate in Hz (S16LE mono) — required with '
            '--format pcm, rejected otherwise.',
        valueHelp: 'hz',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Write the audio to a file instead of stdout. '
            '-o - forces stdout even at a terminal (§1.1).',
        valueHelp: 'file',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Force the stderr feedback channel on even under a pipe '
            '(§5.4-6).',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        negatable: false,
        help: 'Silence the stderr feedback channel except for errors, even '
            'at a terminal.',
      );
  }

  @override
  String get name => 'synthesize';

  @override
  String get description =>
      'Synthesize speech from text on stdin to an audio stream on stdout (the '
      'default verb). Text bytes in, audio out; stdin EOF ends the job. The '
      'stream is self-describing WAV by default.';

  @override
  String get invocation => 'tts ["hello world"] [-d <device>] [-v]';

  @override
  Future<int> run() async {
    final path = resolveTtsDevice(
      argResults!['device'] as String?,
      environment: Platform.environment,
    );

    // Build the output format from --format/--rate (§3.4): pcm demands a triple,
    // wav takes nothing. Both arg errors are EX_USAGE — the user can still fix.
    final formatName = argResults!['format'] as String;
    final rateArg = argResults!['rate'] as String?;
    final TtsOutputFormat? format;
    if (formatName == 'pcm') {
      if (rateArg == null) {
        stderr.writeln('tts: --format pcm requires --rate (headerless audio is '
            'only honest when the consumer states the rate)');
        return 64; // EX_USAGE
      }
      final rate = int.tryParse(rateArg);
      if (rate == null || rate <= 0) {
        stderr.writeln('tts: --rate wants a positive integer in Hz, got '
            '"$rateArg"');
        return 64;
      }
      format = PcmOutput(
        PcmTriple(rate: rate, encoding: PcmEncoding.s16le, channels: 1),
      );
    } else {
      if (rateArg != null) {
        stderr.writeln('tts: --rate applies only to --format pcm');
        return 64;
      }
      format = null; // class default — streaming WAV
    }

    final double? speed;
    final speedArg = argResults!['speed'] as String?;
    if (speedArg == null) {
      speed = null;
    } else {
      speed = double.tryParse(speedArg);
      if (speed == null) {
        stderr.writeln('tts: --speed wants a number, got "$speedArg"');
        return 64;
      }
    }

    // §5.4-4: resolve the sink and refuse a binary payload to a terminal
    // BEFORE the device opens — no wasted synthesis.
    final sinkResolution = resolveTtsSink(
      argResults!['output'] as String?,
      stdoutIsTerminal: stdout.hasTerminal,
    );
    final IOSink out;
    final bool outIsFile;
    File? outputFile;
    switch (sinkResolution) {
      case TtsSinkRefused(:final message):
        stderr.writeln(message);
        return 64; // EX_USAGE
      case TtsSinkResolved(file: null):
        out = stdout;
        outIsFile = false;
      case TtsSinkResolved(file: final file):
        out = file!.openWrite();
        outIsFile = true;
        outputFile = file;
    }

    // §5.4-3: resolve the text source — positional beats piped stdin; with
    // neither, an interactive keyboard read (BEFORE the device opens, so an
    // empty Ctrl-D never wastes a boot).
    final positional =
        argResults!.rest.isEmpty ? null : argResults!.rest.join(' ');
    final textSourceResolution = resolveTtsTextSource(
      positional,
      stdinIsTerminal: stdin.hasTerminal,
    );
    final Stream<List<int>> textIn;
    switch (textSourceResolution) {
      case TtsTextSourcePositional(:final text):
        textIn = Stream.value(utf8.encode(text));
      case TtsTextSourceStdin():
        textIn = stdin;
      case TtsTextSourceInteractive():
        stderr.writeln('tts: reading text from the terminal — type your '
            'text, then Ctrl-D to end');
        final text = await readInteractiveText(stdin);
        if (text.isEmpty) {
          stderr.writeln('tts: no text — pass an argument, pipe text, or '
              'type some (empty input)');
          return 64; // EX_USAGE
        }
        textIn = Stream.value(utf8.encode(text));
    }

    // §5.4-6: the feedback channel's gate, and the intent beat — before the
    // device opens, what was requested.
    final feedbackOn = ttsFeedbackEnabled(
      stderrIsTerminal: stderr.hasTerminal,
      verbose: argResults!['verbose'] as bool,
      quiet: argResults!['quiet'] as bool,
    );
    final voiceArg = argResults!['voice'] as String?;
    if (feedbackOn) {
      stderr.writeln(ttsIntentLine(
        target: outIsFile ? outputFile!.path : 'stdout',
        format: ttsFormatLabel(format),
        voice: voiceArg,
      ));
    }

    final SpeechSynthesisDriver driver;
    try {
      driver = bootTtsDevice(path);
    } on TtsBootException catch (e) {
      stderr.writeln('tts: $e');
      return 3;
    }

    try {
      await runSynthesize(
        driver,
        textIn: textIn,
        out: out,
        voice: voiceArg,
        speed: speed,
        format: format,
        feedbackEnabled: feedbackOn,
      );
    } on TtsFormatError catch (e) {
      stderr.writeln(e);
      return 64; // EX_USAGE — the user must resolve the proposal
    } on DriverError catch (e) {
      stderr.writeln('tts: $e');
      return 1;
    } finally {
      if (outIsFile) await out.close();
    }

    // §5.4-5: a seekable -o file honoring the wav default earns the true
    // lengths — the device's streaming sentinel stands everywhere else
    // (pcm, stdout, -o -).
    if (outIsFile && format == null && outputFile != null) {
      await patchWavFileLengths(outputFile);
    }
    return 0;
  }
}
