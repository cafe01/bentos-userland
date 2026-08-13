import 'package:args/command_runner.dart';

import '../entity_runner.dart';
import '../../git/model/actor.dart';
import '../../git/model/commit.dart';
import '../event.dart';
import 'coordinate.dart';

/// The base every `entity` verb stands on: the runner it writes through, and
/// the two argument readings the whole surface is built from — a bare name for
/// the class-level verbs, a coordinate for the instance-level ones.
abstract base class EntityCommand extends Command<void> {
  EntityCommand(this.cli);

  /// The coreutil this verb writes through. Named `cli` and not `runner`
  /// because `Command.runner` is the args package's own member, and shadowing
  /// it would be the surface fighting its host.
  final EntityRunner cli;

  /// The global `-C` as parsed by the runner's own parser.
  String? get placeOption => globalResults?['place'] as String?;

  /// The first positional, or a usage failure naming what was wanted.
  String positional(String label) {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('$name: <$label> is required');
    return rest.first;
  }

  /// The words after `--`: a program, and the second half of the two verbs
  /// that take one.
  ///
  /// Taken from the raw argument list rather than from `rest`, because the
  /// parser folds both sides of the separator into one list while the two
  /// halves mean different things — before it stand this verb's own
  /// positionals, after it stands somebody else's command line.
  List<String> body() {
    final raw = argResults!.arguments;
    final at = raw.indexOf('--');
    return at < 0 ? const [] : raw.sublist(at + 1);
  }

  /// The `--as-of <sha>` the reading verbs take, or null for the present tip.
  ///
  /// A point in history is a **named argument and never part of the
  /// coordinate**: `<coord>@<sha>:<path>` would put a fifth dimension into the
  /// address, and whether one belongs there is the ontology's question rather
  /// than this surface's.
  ///
  /// It is not a convenience either. A validator stands at the parent of the
  /// act landing and asks whether that act was legal *there*, which is never
  /// the present — so a surface that could only read the tip would push every
  /// historical reading back below the primitive.
  ///
  /// **Spelled `--as-of` because `--at` means *where* in this utility**, and it
  /// says so everywhere: `materialize --at <path>`, `refresh <coord> <path>`.
  /// One flag carrying two dimensions is a defect that only appears in the hand
  /// of whoever types it, which is the axis no assertion touches.
  Commit? pointInHistory() {
    final asOf = argResults!['as-of'] as String?;
    return asOf == null ? null : Commit(asOf);
  }

  /// Declares the identity flags on a verb that writes. Both are options with
  /// no default, because there is no ambient form of either.
  void takesActor() => argParser
    ..addOption(
      'actor',
      help: 'Who is acting. Required — there is no ambient form.',
      valueHelp: 'name',
    )
    ..addOption(
      'actor-email',
      help: 'The address stated beside --actor. Required — no address is '
          'derived from a name, and no configuration of the machine may fill '
          'it.',
      valueHelp: 'addr',
    );

  /// Who is acting, as this invocation stated it — or a **usage refusal**.
  ///
  /// **The refusal fires on silence from any caller whatever**, and no property
  /// of who is asking may soften it: the caller that says nothing is exactly
  /// the one that must be refused, and a fallback here produces a signed lie
  /// rather than a failure. It is usage and not *barred* or *contested* —
  /// nobody refused this act and nothing raced it; the command was not sayable,
  /// and the ref does not move.
  Actor statedActor() {
    final stated = argResults!['actor'] as String?;
    final email = argResults!['actor-email'] as String?;
    final hasName = stated != null && stated.trim().isNotEmpty;
    final hasEmail = email != null && email.trim().isNotEmpty;
    if (!hasName || !hasEmail) {
      usageException(
        '$name: who is acting must be stated — pass --actor <name> '
        '--actor-email <addr>. '
        '${!hasName && !hasEmail ? 'Neither was given' : hasName ? 'No address was given' : 'No name was given'}, '
        'and nothing else may answer: the git identity cascade describes '
        'whoever owns a checkout on this machine, not whoever is acting.',
      );
    }
    return Actor(stated.trim(), email: email.trim());
  }

  /// Declares the point-in-history flag on a verb that reads.
  void takesPointInHistory() => argParser.addOption(
        'as-of',
        help: 'Read as the instance stood at this commit.',
        valueHelp: 'sha',
      );

  /// The first positional read as a coordinate.
  Coordinate coordinate() {
    try {
      return Coordinate.parse(positional('coord'));
    } on FormatException catch (e) {
      usageException('$name: ${e.message}');
    }
  }

  /// The first positional read as a coordinate **that the environment may
  /// complete** — the precedence, in the two steps that exist today:
  ///
  /// 1. **The argument**, whenever it names an instance. It always wins, which
  ///    is what keeps every verb scriptable with no environment at all.
  /// 2. **The environment**, when the argument is a bare name: first the
  ///    occurrence a hook is firing for, then the ontology's own pointer.
  ///
  /// The third step — *the place, when the answer is unambiguous* — is not here
  /// yet, and its absence is visible in the refusal below rather than papered
  /// over by guessing.
  ///
  /// **The occurrence outranks the pointer, and is read only when it speaks of
  /// this same entity.** A hook firing for `a.thing` may wake a command about
  /// `b.thing`, and an instance borrowed across that boundary would send a verb
  /// at an object nobody named.
  (Coordinate, CoordinateSource) ambientCoordinate() {
    final typed = positional('coord');
    if (typed.contains(':')) return (coordinate(), CoordinateSource.argument);

    final occurrenceEntity = cli.env[OccurrenceEnvironment.entity];
    final occurrenceInstance = cli.env[OccurrenceEnvironment.instance];
    if (occurrenceEntity == typed &&
        occurrenceInstance != null &&
        occurrenceInstance.isNotEmpty) {
      return (
        Coordinate(entity: typed, instance: occurrenceInstance),
        CoordinateSource.occurrence,
      );
    }

    final variable = ambientVariableFor(typed);
    final pointed = cli.env[variable];
    if (pointed != null && pointed.isNotEmpty) {
      final Coordinate parsed;
      try {
        parsed = Coordinate.parse(pointed);
      } on FormatException {
        usageException(
          '$name: $variable holds "$pointed", which is not <entity>:<instance>',
        );
      }
      if (parsed.entity != typed) {
        usageException(
          '$name: $variable points at ${parsed.entity} and you named $typed',
        );
      }
      return (parsed, CoordinateSource.pointer);
    }

    usageException([
      '$name: $typed names a class, and this verb acts on an instance',
      'type one — $typed:<instance>',
      'or point at one — export $variable=$typed:<instance>',
    ].join('\n  '));
  }
}
