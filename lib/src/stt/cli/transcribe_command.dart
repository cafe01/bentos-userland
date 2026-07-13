/// `stt transcribe` (the default verb) — bounded audio on stdin to transcript
/// on stdout.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:stt_inference/stt_inference.dart';

import '../../../boot_stt.dart';
import '../device.dart';
import '../feedback.dart';
import '../input_guard.dart';
import '../transcribe.dart';

class TranscribeCommand extends Command<int> {
  TranscribeCommand() {
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
  String get name => 'transcribe';

  @override
  String get description =>
      'Transcribe bounded audio from stdin to text on stdout (the default '
      'verb). Audio bytes in, transcript out; stdin EOF ends the job.';

  @override
  String get invocation => 'cat audio.wav | stt [transcribe] [-d <device>] '
      '[-l <lang>] [-v]';

  @override
  Future<int> run() async {
    // §5.4-3: audio never comes from a keyboard — refuse before the device
    // opens, no interactive read (mirror of tts's stdout guard).
    final inputResolution = resolveSttInput(
      SttInputKind.transcribe,
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
    final path = withVerb(base, 'transcribe');

    // §5.4-6: the feedback channel's gate, and the intent beat — before the
    // device opens, what was requested.
    final feedbackOn = sttFeedbackEnabled(
      stderrIsTerminal: stderr.hasTerminal,
      verbose: argResults!['verbose'] as bool,
      quiet: argResults!['quiet'] as bool,
    );
    final language = argResults!['language'] as String?;
    if (feedbackOn) {
      stderr.writeln(sttIntentLine(source: 'audio', language: language));
    }

    final TranscriptionDriver driver;
    try {
      driver = bootTranscribeDevice(path);
    } on SttBootException catch (e) {
      stderr.writeln('stt: $e');
      return 3;
    }

    try {
      await runTranscribe(
        driver,
        audioIn: stdin,
        out: stdout,
        language: language,
        feedbackEnabled: feedbackOn,
      );
    } on DriverError catch (e) {
      stderr.writeln('stt: $e');
      return 1;
    }
    return 0;
  }
}
