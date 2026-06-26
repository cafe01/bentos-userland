import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/forget_command.dart';
import 'commands/recall_command.dart';
import 'commands/remember_command.dart';
import 'commands/survey_command.dart';

final class MemRunner {
  MemRunner() {
    _runner = CommandRunner<void>(
      'mem',
      'The agent\'s persistent memory — survey, recall, remember, forget.',
    )
      ..addCommand(SurveyCommand())
      ..addCommand(RecallCommand())
      ..addCommand(RememberCommand())
      ..addCommand(ForgetCommand());

    _runner.argParser
      ..addOption('agent', abbr: 'a', help: 'Operate on NAME\'s memory (default: \$BENTOS_AGENT).')
      ..addOption('place', abbr: 'p', help: 'Override the place whose .mem/ store is read (default: CWD).');
  }

  late final CommandRunner<void> _runner;
  int exitCode = 0;

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      exitCode = 64;
    } catch (e) {
      stderr.writeln('mem: $e');
      exitCode = 1;
    }
  }
}
