/// `tts synthesize` (the default, nameless-in-use verb) — bounded text on
/// stdin to an audio stream on stdout.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:bentos_driver_sdk/bentos_driver_sdk.dart' show DriverError;
import 'package:tts_inference/tts_inference.dart';

import '../../../boot_tts.dart';
import '../device.dart';
import '../synthesize.dart';

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
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print run metadata (model · format · voice · timing) to '
            'stderr.',
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
  String get invocation => 'echo "hello" | tts [synthesize] [-d <device>] [-v]';

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
        textIn: stdin,
        out: stdout,
        voice: argResults!['voice'] as String?,
        speed: speed,
        format: format,
        verbose: argResults!['verbose'] as bool,
      );
    } on TtsFormatError catch (e) {
      stderr.writeln(e);
      return 64; // EX_USAGE — the user must resolve the proposal
    } on DriverError catch (e) {
      stderr.writeln('tts: $e');
      return 1;
    }
    return 0;
  }
}
