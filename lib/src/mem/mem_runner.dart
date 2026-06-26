import 'dart:io' as io;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'commands/forget_command.dart';
import 'commands/recall_command.dart';
import 'commands/remember_command.dart';
import 'commands/survey_command.dart';
import 'mem_context.dart';
import 'model/mem_resolver.dart';

final class MemRunner {
  MemRunner({
    StringSink? out,
    StringSink? err,
    FileSystem? fileSystem,
    this.stdinContent,
    Map<String, String>? environment,
  })  : _out = out ?? io.stdout,
        _err = err ?? io.stderr,
        _fileSystem = fileSystem ?? const LocalFileSystem(),
        _environment = environment ?? io.Platform.environment {
    _runner = CommandRunner<void>(
      'mem',
      'The agent\'s persistent memory — survey, recall, remember, forget.',
    )
      ..addCommand(SurveyCommand(this))
      ..addCommand(RecallCommand(this))
      ..addCommand(RememberCommand(this))
      ..addCommand(ForgetCommand(this));

    _runner.argParser
      ..addOption('agent',
          abbr: 'a',
          help: 'Operate on NAME\'s memory (default: \$BENTOS_AGENT).')
      ..addOption('place',
          abbr: 'p',
          help: 'Override the place whose .mem/ store is read (default: CWD).');
  }

  /// Pre-canned stdin content for hermetic tests; null = use real stdin.
  final String? stdinContent;

  final StringSink _out;
  final StringSink _err;
  final FileSystem _fileSystem;
  final Map<String, String> _environment;
  late final CommandRunner<void> _runner;
  int exitCode = 0;

  StringSink get out => _out;
  StringSink get err => _err;
  FileSystem get fileSystem => _fileSystem;

  /// Build the execution context from global flags; returns null and writes an
  /// error if the agent cannot be resolved.
  MemContext? buildContext(ArgResults globalResults) {
    final agent = (globalResults['agent'] as String?) ?? _environment['BENTOS_AGENT'];
    if (agent == null || agent.isEmpty) {
      _err.writeln('mem: no agent specified. Use -a/--agent or set \$BENTOS_AGENT.');
      exitCode = 1;
      return null;
    }
    final place = (globalResults['place'] as String?) ?? io.Directory.current.path;
    final resolver = MemResolver(agent: agent, fileSystem: _fileSystem);
    return MemContext(
      resolver: resolver,
      place: place,
      out: _out,
      err: _err,
      fileSystem: _fileSystem,
      stdinContent: stdinContent,
    );
  }

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
