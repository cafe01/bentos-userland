import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'commands/forget_command.dart';
import 'commands/recall_command.dart';
import 'commands/remember_command.dart';
import 'commands/survey_command.dart';

final class MemRunner {
  MemRunner({StringSink? out, StringSink? err, FileSystem? fileSystem, this.stdinContent})
      : _out = out ?? io.stdout,
        _err = err ?? io.stderr,
        // ignore: avoid_redundant_argument_values
        _fileSystem = fileSystem ?? const LocalFileSystem() {
    _runner = CommandRunner<void>(
      'mem',
      'The agent\'s persistent memory — survey, recall, remember, forget.',
    )
      ..addCommand(SurveyCommand())
      ..addCommand(RecallCommand())
      ..addCommand(RememberCommand())
      ..addCommand(ForgetCommand());

    _runner.argParser
      ..addOption('agent',
          abbr: 'a',
          help: 'Operate on NAME\'s memory (default: \$BENTOS_AGENT).')
      ..addOption('place',
          abbr: 'p',
          help:
              'Override the place whose .mem/ store is read (default: CWD).');
  }

  /// Pre-canned stdin content for hermetic tests; null = use real stdin.
  final String? stdinContent;

  // ignore: unused_field
  final StringSink _out;
  final StringSink _err;
  // ignore: unused_field
  final FileSystem _fileSystem;
  late final CommandRunner<void> _runner;
  int exitCode = 0;

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      _err.writeln(e.message);
      exitCode = 64;
    } catch (e) {
      _err.writeln('mem: $e');
      exitCode = 1;
    }
  }
}
