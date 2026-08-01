import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'commands/acting_commands.dart';
import 'commands/entity_commands.dart';
import 'commands/instance_commands.dart';
import 'commands/plumbing_commands.dart';
import 'commands/reacting_commands.dart';
import 'entity.dart';

/// The `entity` coreutil's command runner — the API on the PATH, and the
/// **generic client of the platform**: knowing only the interaction model, it
/// says what a thing is, what may be done to it, and arms behaviour on what it
/// publishes, with no integration written for the thing in particular.
///
/// # The four families are the ontology's own
///
/// A thing is brought into being or brought here; it has objects; things are
/// done to those objects; and what was done wakes whoever cared. Nothing in the
/// surface is Git's vocabulary — `branch`, `worktree` and `update-ref` are what
/// the verbs compile to, one floor down.
///
/// # It lists actions; it never performs them
///
/// `info` prints the vocabulary a type declares, and that is reflection.
/// **Invoke does not exist**: there is no verb asking an entity to do
/// something, because acting is writing and the writer is the caller.
///
/// # Two words the library gave up, the shell keeps
///
/// `new` is a reserved word in Dart and the API spells the constructor
/// otherwise; at a shell it is simply the right word, and there are no handles
/// here to distinguish from births — every line typed is an act. `path`
/// likewise: the library refuses a public repository directory because a caller
/// holding one runs Git itself, and here it stands as a named escape hatch for
/// the person who has decided to go below the ontology.
final class EntityRunner {
  EntityRunner({StringSink? out, StringSink? err, String? currentDirectory})
      : out = out ?? io.stdout,
        err = err ?? io.stderr,
        _cwdOverride = currentDirectory {
    _runner = CommandRunner<void>(
      'entity',
      'The WHAT organ — say what a thing is, act on it, and arm what it publishes.',
    )
      ..argParser.addOption(
        'place',
        abbr: 'C',
        help: 'The vantage name resolution walks up from.',
        valueHelp: 'place',
      )
      ..addCommand(CreateCommand(this))
      ..addCommand(InstallCommand(this))
      ..addCommand(WhichCommand(this))
      ..addCommand(InfoCommand(this))
      ..addCommand(PublishCommand(this))
      ..addCommand(RemotesCommand(this))
      ..addCommand(NewCommand(this))
      ..addCommand(LsCommand(this))
      ..addCommand(LogCommand(this))
      ..addCommand(ShowCommand(this))
      ..addCommand(ActCommand(this))
      ..addCommand(ReadCommand(this))
      ..addCommand(MaterializeCommand(this))
      ..addCommand(OnCommand(this))
      ..addCommand(OffCommand(this))
      ..addCommand(ListenersCommand(this))
      ..addCommand(ResolveCommand(this))
      ..addCommand(TipCommand(this))
      ..addCommand(PathCommand(this))
      ..addCommand(WorkCommand(this))
      ..addCommand(CommitCommand(this))
      ..addCommand(ReleaseCommand(this));
  }

  final StringSink out;
  final StringSink err;
  final String? _cwdOverride;

  late final CommandRunner<void> _runner;

  /// The process's answer. **0 ok · 64 usage · 3 refused** — usage is
  /// `EX_USAGE`, spoken the same way `place` and `mem` speak it, and refusal
  /// earns a code of its own because it is an ordinary outcome of concurrent
  /// agency that a caller must be able to retry on without parsing prose.
  int exitCode = 0;

  static const int okCode = 0;
  static const int usageCode = 64;
  static const int refusedCode = 3;

  /// The working directory — injected override, else the process's own.
  String get cwd => _cwdOverride ?? io.Directory.current.path;

  /// The vantage a name resolves from: `-C` when given, else the working
  /// directory. Relative paths resolve against the injected [cwd], never the
  /// process's own.
  String vantage(String? placeArg) {
    final target = placeArg ?? cwd;
    final abs = p.isAbsolute(target) ? target : p.join(cwd, target);
    return p.normalize(abs);
  }

  /// A handle to [name], anchored at the vantage. Cheap and creates nothing —
  /// the resolution happens when a member is read.
  Entity entityNamed(String name, {String? place}) =>
      Entity(name, from: vantage(place));

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = usageCode;
    }
  }
}
