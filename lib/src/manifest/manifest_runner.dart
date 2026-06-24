import 'dart:io';

import 'package:args/command_runner.dart';

import 'build_command.dart';
import 'check_command.dart';
import 'edit_command.dart';
import 'ls_command.dart';
import 'new_command.dart';

/// The `manifest` coreutil — genesis engine of the periodic table.
final class ManifestRunner extends CommandRunner<int> {
  static const _knownSubcommands = {'build', 'check', 'edit', 'ls', 'new', 'help'};

  ManifestRunner() : super('manifest', 'Conjure a being from its particles.') {
    addCommand(BuildCommand());
    addCommand(NewCommand());
    addCommand(LsCommand());
    addCommand(CheckCommand());
    addCommand(EditCommand());
  }

  /// Rewrite args so that a bare FQDN (or `-`) routes to `build` by default.
  ///
  /// Rules:
  ///   - Empty args          → ['build']          (stdin mode)
  ///   - First arg is a flag → pass through        (--help, --version, …)
  ///   - First arg is a known subcommand → pass through
  ///   - Anything else       → prepend 'build'
  static List<String> normalizeArgs(List<String> args) {
    if (args.isEmpty) return ['build'];
    final first = args.first;
    if (first == '-') return ['build', ...args]; // stdin alias
    if (first.startsWith('-')) return args; // global flag (--help, --version, …)
    if (_knownSubcommands.contains(first)) return args;
    return ['build', ...args];
  }

  @override
  Future<int?> run(Iterable<String> args) async {
    try {
      return await super.run(normalizeArgs(args.toList()));
    } on UsageException catch (e) {
      stderr.writeln(e.message);
      if (e.message.contains('Could not find an option')) {
        stderr.writeln('  Run `manifest edit --help` to see the vocabulary.');
      }
      return 64; // EX_USAGE
    }
  }
}
