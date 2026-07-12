/// `stt transcribe` (the default verb) — bounded audio on stdin to transcript
/// on stdout.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:stt_inference/stt_inference.dart';

import '../../../boot_stt.dart';
import '../device.dart';
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
        help: 'Print run metadata (model · language · duration · timing) '
            'to stderr.',
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
    final base = resolveSttDevice(
      argResults!['device'] as String?,
      environment: Platform.environment,
    );
    final path = withVerb(base, 'transcribe');

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
        language: argResults!['language'] as String?,
        verbose: argResults!['verbose'] as bool,
      );
    } on DriverError catch (e) {
      stderr.writeln('stt: $e');
      return 1;
    }
    return 0;
  }
}
