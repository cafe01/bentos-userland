import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../place/place.dart';
import 'commands/acting_commands.dart';
import 'commands/entity_commands.dart';
import 'commands/instance_commands.dart';
import 'commands/plumbing_commands.dart';
import 'commands/coordinate.dart';
import 'commands/reacting_commands.dart';
import 'entity.dart';
import 'instance.dart';

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

  /// The process's answer. **0 ok · 1 not found · 3 refused · 64 usage.**
  ///
  /// Usage is `EX_USAGE`, and refusal earns a code of its own because it is an
  /// ordinary outcome of concurrent agency that a caller must be able to retry
  /// on without parsing prose.
  ///
  /// **Absence is not usage.** `which` is precisely the presence test — a
  /// script asks *is this installed here?* and branches on the answer — so
  /// collapsing a legitimately absent entity into the usage code would make it
  /// indistinguishable from a mistyped flag, and destroy the only question the
  /// verb was called to answer. The generic failure is `which(1)`'s own, and
  /// ours was merely left vacant when usage moved to 64.
  int exitCode = 0;

  static const int okCode = 0;
  static const int notFoundCode = 1;
  static const int refusedCode = 3;
  static const int usageCode = 64;

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

  /// A handle to the instance a coordinate selects. Cheap and creates nothing,
  /// like every handle here — the instance need not exist.
  Instance instanceAt(Coordinate coord, {String? place}) =>
      entityNamed(coord.entity, place: place).instance(coord.instance);

  /// The place whose registration answers to [name], walking **up** from the
  /// vantage — nearest wins, the same law `Entity` resolves its repository by.
  ///
  /// The coreutil performs the walk itself here because what `which` reports is
  /// the *place*, and the API deliberately surfaces no location at all: a
  /// caller holding one runs Git in it.
  io.Directory installedAt(String name, {String? place}) {
    final anchor = vantage(place);
    for (Place? at = Place(anchor); at != null; at = at.parent) {
      if (at.lookup(name) != null) return at.root;
    }
    throw EntityNotInstalled(name, anchor);
  }

  /// A source as this process must read it: a local path against [cwd], a URL
  /// or an ssh shorthand exactly as written.
  String locate(String source) => locateSource(source, from: cwd);

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = usageCode;
    } on EntityNotInstalled catch (e) {
      err.writeln('$e');
      exitCode = notFoundCode;
    } on StateError catch (e) {
      // The two the API raises are *no genesis* and *not born* — both the
      // absence of a thing the caller named, which is the not-found answer and
      // not a fault in the machine.
      err.writeln('entity: ${e.message}');
      exitCode = notFoundCode;
    }
  }
}
