import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../entity_runner.dart';
import '../manifest.dart';
import 'coordinate.dart';
import 'entity_command.dart';

/// `entity run <coord> <function> [args...]` — a caller names a verb and the
/// entity's own body runs, with the context already laid.
///
/// # It is not `invoke`
///
/// Nothing here asks an entity to do something: an entity is a thing and never
/// a who, and acting is still writing. What this resolves is a **file** the
/// entity ships and the manifest names, and what it does with it is `exec` and
/// nothing else — no noun is validated, no deposit is honoured, no `on:` row is
/// read. A function that writes does so by taking an act itself, exactly as a
/// caller typing the same command would. Meaning stays one floor up, always.
///
/// # The context is the contract
///
/// Four variables, and their whole purpose is that **no body ever asks where it
/// is**: the place it was resolved in, the entity, the instance, and the
/// coordinate the caller typed. The instance travels **verbatim** — it is not
/// looked up, not required to be born, not read. A function that needs it to
/// exist finds that out itself, which is the only reading under which `run`
/// interprets nothing.
///
/// # The coordinate may come from the environment
///
/// A bare entity name is completed by the ambient coordinate — the occurrence a
/// hook is firing for, then the ontology's own pointer — and that is what makes
/// a **manifest-armed line possible at all**: at install time no instance
/// exists, so the line is armed on `*` and names none, and the instance the
/// event landed on reaches this verb through the shim's exports. A typed
/// coordinate always wins, so nothing scripted changes meaning.
///
/// # Transparent, not replaced
///
/// Dart cannot `exec`, so this stays as the child's parent and inherits all
/// three streams — **stdin included**, or a body that reads is a body that
/// hangs. The child's exit code is this process's, unedited.
final class RunCommand extends EntityCommand {
  RunCommand(super.cli);

  @override
  String get name => 'run';

  @override
  String get description => 'Run a function the entity declares.';

  /// **Option parsing stops at the first positional.** Everything after the
  /// function's name belongs to the function, and a parser that kept reading
  /// would refuse `--verbose` on behalf of a program it knows nothing about.
  /// The trailing `--` other verbs need is therefore not required here — the
  /// caller writes the command line the body's own author documented.
  @override
  ArgParser get argParser => _parser;
  final ArgParser _parser = ArgParser(allowTrailingOptions: false);

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.length < 2) usageException('run: <coord> <function> are required');
    final (coord, _) = ambientCoordinate();
    if (coord.path != null) {
      // A path selects content inside an instance, and running is not reading.
      usageException('run: expected <entity>:<instance>, with no path');
    }
    final wanted = rest[1];
    final arguments = rest.sublist(2);

    final entity = cli.entityNamed(coord.entity, place: placeOption);
    // The manifest is read from the ref, always: one source for the contract,
    // and the same commit the bytes below are required to have come from.
    final Manifest declared = entity.manifest;

    if (!declared.functions.containsKey(wanted)) {
      // Absence, and not usage: the caller spelled a verb this entity does not
      // have, which is the same answer as any other thing we could not find.
      cli.err.writeln(
        "entity run: ${entity.name} declares no function '$wanted'",
      );
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    final exec = declared.functions[wanted];
    if (exec == null) {
      cli.err.writeln(
        "entity run: ${entity.name} declares '$wanted' with no executable",
      );
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }

    final staged = entity.stagedClass;
    final standing = staged.at;
    final holds = entity.genesis;
    // Resolved here and not only where the child is started, because a refusal
    // that names a cure has to name the **vantage** too: a bare name resolves by
    // walking up from wherever the reader is standing, and a cure retyped from
    // another directory finds another installation, answers zero, and moves
    // nothing. Which is exactly what it did the first time it was tried by hand.
    final place = cli.installedAt(coord.entity, place: placeOption);
    // The one line every refusal below ends on. **A refusal that names no cure
    // is refused by halves**: the guard is right to stop, and a reader left
    // holding a sentence has nowhere to go. Written once because all three
    // states are cured by the same act — make this directory be the genesis
    // this installation holds — and a second spelling would rot apart from the
    // first.
    final cure = 'entity -C ${place.path} refresh ${entity.name}:$_genesisId '
        '${staged.directory.path}';

    if (standing == null) {
      final blocked = staged.directory.existsSync() &&
          staged.directory.listSync().isNotEmpty;
      cli.err.writeln([
        if (blocked)
          'entity run: ${entity.name} has no class tree at '
              '${staged.directory.path} — a directory this installation never '
              'registered stands there'
        else
          'entity run: ${entity.name} has no class tree at '
              '${staged.directory.path}',
        'the executables it declares are not on disk',
        if (blocked) 'move what stands there aside, then: $cure' else 'stand it up: $cure',
      ].join('\n  '));
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    if (standing != holds) {
      // **Never repaired here.** A verb that quietly makes itself right runs
      // bodies this place does not declare, exits zero, and tells nobody — the
      // one failure worse than not running at all.
      cli.err.writeln([
        'entity run: ${entity.name} stands at ${standing.short} and this '
            'installation holds ${holds.short}',
        'running it would execute bodies this place does not declare',
        'bring it forward: $cure',
      ].join('\n  '));
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }

    final program = p.join(staged.directory.path, exec);
    final Process child;
    try {
      child = await Process.start(
        program,
        arguments,
        environment: {
          OccurrenceEnvironment.place: place.path,
          OccurrenceEnvironment.entity: entity.name,
          OccurrenceEnvironment.instance: coord.instance,
          OccurrenceEnvironment.coordinate: '${coord.entity}:${coord.instance}',
        },
        // The caller's own, untouched: context arrives by environment, so
        // relocating the body would be this verb inventing a fact nobody asked
        // it to invent.
        workingDirectory: cli.cwd,
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (e) {
      cli.err.writeln([
        "entity run: cannot run '$wanted': ${e.message}",
        '${entity.name} declares it at $exec, looked for in '
            '${staged.directory.path}',
      ].join('\n  '));
      cli.exitCode = EntityRunner.notFoundCode;
      return;
    }
    cli.exitCode = await child.exitCode;
  }

  /// The branch name the class stands on, as a coordinate spells it. Named here
  /// only so the cure a refusal prints is the string a caller can retype.
  static const String _genesisId = 'genesis';
}
