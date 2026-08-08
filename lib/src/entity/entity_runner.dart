import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../git/git.dart';
import '../place/place.dart';
import 'action.dart';
import 'commands/acting_commands.dart';
import 'commands/entity_commands.dart';
import 'commands/instance_commands.dart';
import 'commands/coordinate.dart';
import 'commands/plumbing_commands.dart';
import 'commands/reacting_commands.dart';
import 'commands/running_commands.dart';
import 'entity.dart';
import 'installation_life.dart';
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
/// `run` is not that verb and does not become it. It resolves a name to a
/// **file the entity ships** and executes it — the caller's own program,
/// reached by the name its author gave it instead of by a layout the caller had
/// to learn. Nothing about the entity's state moves because it ran, and a body
/// that means to write takes an act like anybody else.
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
  EntityRunner({
    StringSink? out,
    StringSink? err,
    String? currentDirectory,
    Map<String, String>? environment,
  })  : out = out ?? io.stdout,
        err = err ?? io.stderr,
        _cwdOverride = currentDirectory,
        _envOverride = environment {
    _runner = _Surface(
      'entity',
      'The WHAT organ — say what a thing is, act on it, and arm what it publishes.',
      // `this.out`: the bare name here is the constructor's own nullable
      // parameter, and the field beside it is the resolved sink.
      sink: this.out,
    )
      ..argParser.addOption(
        'place',
        abbr: 'C',
        help: 'The vantage name resolution walks up from.',
        valueHelp: 'place',
      )
      ..addCommand(CreateCommand(this))
      ..addCommand(InstallCommand(this))
      ..addCommand(RefitCommand(this))
      ..addCommand(UpgradeCommand(this))
      ..addCommand(WhichCommand(this))
      ..addCommand(InfoCommand(this))
      ..addCommand(PublishCommand(this))
      ..addCommand(FetchCommand(this))
      ..addCommand(RemotesCommand(this))
      ..addCommand(NewCommand(this))
      ..addCommand(LsCommand(this))
      ..addCommand(LogCommand(this))
      ..addCommand(ShowCommand(this))
      ..addCommand(ActCommand(this))
      ..addCommand(RunCommand(this))
      ..addCommand(ReadCommand(this))
      ..addCommand(MaterializeCommand(this))
      ..addCommand(RefreshCommand(this))
      ..addCommand(OnCommand(this))
      ..addCommand(OnceCommand(this))
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
  final Map<String, String>? _envOverride;

  /// Content, verbatim. A separate channel because an instance may hold
  /// anything and [out] is a text sink: `read` must be able to hand back a
  /// PNG as faithfully as a line of YAML.
  void writeBytes(List<int> bytes) {
    if (identical(out, io.stdout)) {
      io.stdout.add(bytes);
      return;
    }
    out.write(String.fromCharCodes(bytes));
  }

  /// What a body said, passed to the operator without being published. An
  /// acting body's own streams are noise on stdout, where the landed sha is
  /// the whole answer.
  void writeThrough(List<int> bytes) => err.write(String.fromCharCodes(bytes));

  late final _Surface _runner;

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

  /// The request was declined and nothing happened: a gate said no, or this
  /// coreutil itself refused to touch what was there. Retrying changes nothing.
  /// The `.attempted` gate is one source of this code, not its definition.
  static const int barredCode = 3;

  /// The ref moved under the act. Nobody decided anything, and a script that
  /// re-reads the tip and tries again will terminate — which is the whole
  /// reason this is a number of its own and not [barredCode]: a distinction
  /// that does not survive the process boundary does not exist.
  static const int contestedCode = 4;

  /// Two lines advanced from a common ancestor. Nothing failed and nothing will
  /// change by trying again — a script that loops here loops forever, which is
  /// why this cannot share a number with [contestedCode].
  static const int divergedCode = 5;

  static const int usageCode = 64;

  /// The working directory — injected override, else the process's own.
  String get cwd => _cwdOverride ?? io.Directory.current.path;

  /// The environment this run reads its ambient coordinate from — injected
  /// override, else the process's own.
  ///
  /// Injected for the same reason [cwd] is: a claim about *what a verb does when
  /// the environment says so* cannot be proven by a gate that has no way to make
  /// the environment say anything.
  Map<String, String> get env => _envOverride ?? io.Platform.environment;

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

  /// An act's outcome, as a line and a number.
  ///
  /// A method of the runner and not an extension on it: `dart:io` exports a
  /// top-level `exitCode` setter, which an unqualified assignment inside an
  /// extension binds to in preference to the runner's own field — the number
  /// then lands on the process while the caller reads zero, and nothing says
  /// so. Here the field is the only `exitCode` in scope.
  void report(ActionResult result) {
    switch (result) {
      case Landed(:final action):
        out.writeln(action.commit.sha);
      case Barred(:final reason):
        err.writeln('entity: barred — $reason');
        exitCode = barredCode;
      case Contested(:final expected, :final found):
        err.writeln([
          'entity: contested',
          if (expected != null) 'expected ${expected.short}',
          if (found != null) 'found ${found.short}',
        ].join(', '));
        exitCode = contestedCode;
      case Diverged(:final local, :final remote):
        err.writeln(
          'entity: diverged, local ${local.short}, remote ${remote.short}',
        );
        exitCode = divergedCode;
    }
  }

  /// A source as this process must read it: a local path against [cwd], a URL
  /// or an ssh shorthand exactly as written.
  String locate(String source) => locateSource(source, from: cwd);

  /// The surface as a block of text, in the ontology's own order.
  String get surface => _runner.usage;

  Future<void> run(List<String> args) async {
    try {
      await _runner.run(args);
    } on UsageException catch (e) {
      err.writeln(e.message);
      exitCode = usageCode;
    } on EntityNotInstalled catch (e) {
      err.writeln('$e');
      exitCode = notFoundCode;
    } on EntityAlreadyInstalled catch (e) {
      // Refusal, and the same reading as a worktree that is not ours: nothing
      // was cloned, registered or armed, and what a caller must be able to
      // branch on is *I did not touch what is there*.
      err.writeln('entity: barred — $e');
      exitCode = barredCode;
    } on WorktreeNotOurs catch (e) {
      // Refusal and not a fault: the caller named a directory this repository
      // does not hold, and the answer a script must be able to branch on is
      // *I did not touch it* — which a zero could never say.
      err.writeln('entity: barred — $e');
      exitCode = barredCode;
    } on NoRemoteDeclared catch (e) {
      // An absence and never a refusal: nothing was declined, and the thing
      // named is simply not there. The message already names both roads out of
      // the dead end — `publish` to give it an origin, `refit` for the local
      // half — and it is printed here because a string that never leaves the
      // library has not reached the person it was written for.
      err.writeln('entity: $e');
      exitCode = notFoundCode;
    } on GenesisNotAtRemote catch (e) {
      // The class-level twin of [InstanceNotAtRemote], and classified
      // identically: the remote holds nothing under that name.
      err.writeln('entity: $e');
      exitCode = notFoundCode;
    } on GenesisContested catch (e) {
      // The ref moved under the act. Nobody decided anything, and a caller that
      // re-reads and tries again terminates.
      err.writeln('entity: contested — $e');
      exitCode = contestedCode;
    } on GenesisDiverged catch (e) {
      // Two lines from a common ancestor. Nothing was refused and nothing will
      // change by trying again, which is why it cannot share a number with a
      // contest: a script may loop on that one and must not loop on this.
      err.writeln('entity: diverged — $e');
      exitCode = divergedCode;
    } on InstanceNotAtRemote catch (e) {
      // The remote holds nothing under that name. Not a refusal — the same
      // answer this coreutil gives for every other thing it could not find.
      err.writeln('entity: $e');
      exitCode = notFoundCode;
    } on BodyNotStartable catch (e) {
      // The body never started, so nothing was written and nothing landed —
      // the caller named something that is not there, which is the same answer
      // as any other thing this coreutil could not find.
      err.writeln('$e');
      exitCode = notFoundCode;
    } on StateError catch (e) {
      // The two the API raises are *no genesis* and *not born* — both the
      // absence of a thing the caller named, which is the not-found answer and
      // not a fault in the machine.
      err.writeln('entity: ${e.message}');
      exitCode = notFoundCode;
    } on io.ProcessException catch (e) {
      // The substrate refused, and its word travels. **A coreutil never exits
      // by stack trace**: a trace names a Dart frame to a person holding a
      // terminal, exits 255, and says nothing a script can read — where the
      // message underneath it ("destination path already exists") is the whole
      // of what happened. Whatever this floor cannot name is still a failure,
      // and the generic failure is 1.
      err.writeln('entity: ${e.message.trim()}');
      exitCode = notFoundCode;
    } on Object catch (e) {
      // An act whose body failed produced no state worth landing, and the
      // number is the body's own: the caller wrote that program and knows what
      // its codes mean, so inventing one here would discard the only report
      // the failure actually made.
      final failed = bodyFailureCode(e);
      if (failed == null) rethrow;
      exitCode = failed;
    }
  }
}

/// The runner, with **the surface printed in the ontology's own order** rather
/// than in the alphabet's.
///
/// `args` builds its command list with `names.toList()..sort()`, so the help
/// screen has always presented the verbs sorted by first letter — an order
/// nobody designed, in which `refit` and `upgrade` are three verbs apart and
/// the families the ontology is actually made of do not appear at all. The
/// verbs are the product's ontology, not this utility's alphabet, and a reader
/// choosing between two verbs must not have to find the second one somewhere
/// else in the list.
///
/// This overrides ordering and grouping, and **nothing else**: every verb's own
/// `description` is printed verbatim, and a command that no family below claims
/// still appears, under [_unclaimed] — a surface that silently dropped a
/// registered verb would be a worse failure than the one being cured.
final class _Surface extends CommandRunner<void> {
  _Surface(super.executableName, super.description, {required this.sink});

  /// Where usage is printed. The base class prints with `print`, which reaches
  /// the process's own stdout and not the sink this coreutil was handed — so a
  /// caller holding the streams would receive nothing at all.
  final StringSink sink;

  /// The families, in the order the surface is written, and the verbs inside
  /// each in the order a reader meets them — never alphabetical.
  static const Map<String, List<String>> _families = {
    'the entity': [
      'create',
      'install',
      'refit',
      'upgrade',
      'which',
      'info',
      'publish',
      'remotes',
    ],
    'instances': ['new', 'ls', 'log', 'show', 'fetch'],
    'acting': ['run', 'act', 'read', 'materialize', 'refresh'],
    'subscribing': ['on', 'once', 'off', 'listeners'],
    'plumbing': [
      'resolve',
      'tip',
      'path',
      'work',
      'commit',
      'release',
    ],
  };

  /// Where a registered verb no family claims is printed. `help` lands here by
  /// right — it is the utility's own and not one of the ontology's — and so
  /// does anything registered later and not filed above, which is the point:
  /// the failure this must never have is a verb that exists and is invisible.
  static const String _unclaimed = 'the utility itself';

  @override
  void printUsage() => sink.writeln(usage);

  @override
  String get usage {
    final buffer = StringBuffer()
      ..writeln(description)
      ..writeln()
      ..writeln('Usage: $invocation')
      ..writeln()
      ..writeln('Global options:')
      ..writeln(argParser.usage)
      ..writeln();

    final claimed = {for (final f in _families.values) ...f};
    final leftovers = commands.keys
        .where((name) => !claimed.contains(name))
        .where((name) => !commands[name]!.aliases.contains(name))
        .toList();

    final groups = <String, List<String>>{
      for (final entry in _families.entries)
        entry.key: [
          for (final verb in entry.value)
            if (commands.containsKey(verb)) verb,
        ],
      if (leftovers.isNotEmpty) _unclaimed: leftovers,
    };

    final width = commands.keys
        .map((name) => name.length)
        .fold(0, (a, b) => a > b ? a : b);

    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      buffer.writeln(entry.key);
      for (final verb in entry.value) {
        buffer.writeln(
          '  ${verb.padRight(width + 2)}${commands[verb]!.description}',
        );
      }
      buffer.writeln();
    }

    buffer.write(
      'Run "$executableName help <command>" for more information about a '
      'command.',
    );
    return buffer.toString();
  }
}
