/// `stt live` — an unbounded full-duplex session: streaming audio on stdin to
/// committed transcript lines on stdout, one utterance per line.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:stt_inference/stt_inference.dart';

import '../../../boot_stt.dart';
import '../device.dart';
import '../feedback.dart';
import '../input_guard.dart';
import '../live.dart';

class LiveCommand extends Command<int> {
  LiveCommand() {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        help: 'Device base /dev/stt/<vendor>/<model> '
            '(overrides $sttDeviceEnvVar and the default). '
            'Never carries the protocol segment — the verb appends it.',
      )
      ..addOption(
        'language',
        abbr: 'l',
        help: 'Hint the source language (BCP-47). Omit to autodetect.',
        valueHelp: 'code',
      )
      ..addOption(
        'rate',
        abbr: 'r',
        help: 'Assert the input PCM sample rate in Hz (S16LE mono). Omit to '
            'take the device default — the canonical 16000, or the sole rate '
            'the device offers.',
        valueHelp: 'hz',
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
  String get name => 'live';

  @override
  String get description =>
      'Stream live audio from stdin to committed transcript lines on stdout. '
      'stdin is RAW PCM (S16LE mono) off a live capture source — a microphone, '
      'not a file. Full-duplex: text flows while audio flows; stdin EOF drains '
      'the session. Partial hypotheses and corrections are dropped — only '
      'committed finals are emitted, one per line. To transcribe an existing '
      'audio file (WAV, self-describing header), use `stt transcribe`.';

  @override
  String get invocation =>
      'arecord -f S16_LE -r 24000 -t raw | stt live '
      '[-d <device>] [-l <lang>] [-r <hz>] [-v]';

  @override
  String get usageFooter =>
      '\nThe input is a raw PCM byte stream from a mic — set arecord (or your '
      'capture tool) to S16LE mono at the device rate, and pass the same rate '
      'via -r when the device is not the canonical 16 kHz.';

  @override
  Future<int> run() async {
    // §5.4-3: audio never comes from a keyboard — refuse before the device
    // opens, no interactive read (mirror of tts's stdout guard).
    final inputResolution = resolveSttInput(
      SttInputKind.live,
      stdinIsTerminal: stdin.hasTerminal,
    );
    if (inputResolution is SttInputRefused) {
      stderr.writeln(inputResolution.message);
      return 64; // EX_USAGE
    }

    final base = resolveSttDevice(
      argResults!['device'] as String?,
      environment: Platform.environment,
    );
    final path = withVerb(base, 'live');

    final rateArg = argResults!['rate'] as String?;
    final int? rate;
    if (rateArg == null) {
      rate = null;
    } else {
      rate = int.tryParse(rateArg);
      if (rate == null || rate <= 0) {
        stderr.writeln('stt: --rate wants a positive integer in Hz, got '
            '"$rateArg"');
        return 64; // EX_USAGE
      }
    }

    // §5.4-6: the feedback channel's gate, and the intent beat — before the
    // device opens, what was requested.
    final feedbackOn = sttFeedbackEnabled(
      stderrIsTerminal: stderr.hasTerminal,
      verbose: argResults!['verbose'] as bool,
      quiet: argResults!['quiet'] as bool,
    );
    final language = argResults!['language'] as String?;
    if (feedbackOn) {
      stderr.writeln(sttIntentLine(
        source: 'live audio',
        language: language,
        format: rate != null ? '${rate}Hz' : null,
      ));
    }

    final LiveTranscriptionDriver<Object?> driver;
    try {
      driver = bootLiveDevice(path);
    } on SttBootException catch (e) {
      stderr.writeln('stt: $e');
      return 3;
    }

    try {
      await runLive(
        driver,
        audioIn: stdin,
        out: stdout,
        language: language,
        rate: rate,
        feedbackEnabled: feedbackOn,
      );
    } on SttFormatError catch (e) {
      stderr.writeln(e);
      return 64; // EX_USAGE — the user must resolve the format
    } on DriverError catch (e) {
      stderr.writeln('stt: $e');
      return 1;
    }
    return 0;
  }
}
