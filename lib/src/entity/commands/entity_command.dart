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

  /// **The one-line grammar `--help` prints, derived from [positionalLabels]
  /// and nothing hand-written.** Every verb here is a leaf added directly to
  /// the root runner, so the args package's own parent walk always resolves
  /// to `<executable> <name>`; what varies verb to verb is exactly the
  /// positionals and, where declared, the body or trailing-args marker —
  /// the same two facts [requirePositionals] already reads.
  @override
  String get invocation {
    final words = [
      for (final label in positionalLabels) '<$label>',
      if (_takesBody) '-- <command>',
      if (_takesTrailingArgs) '[args...]',
    ];
    final prefix = '${runner!.executableName} $name';
    return words.isEmpty ? prefix : '$prefix ${words.join(' ')}';
  }

  /// **This verb's own positionals — the words before `--`, and never one of
  /// somebody else's command line.**
  ///
  /// The parser folds both sides of the separator into `rest`, so every arity
  /// question asked of `rest` counts the body's words as if the caller had
  /// typed them: `act <coord> -- git status` reads three positionals, passes a
  /// `rest.length < 2` guard, and lands an act named `git`. A guard that admits
  /// a malformed command line is worse than no guard, because what it admits is
  /// signed and durable.
  ///
  /// The body is taken from the raw argument list by [body], and the raw list
  /// is where the separator still stands — so the count of words after it is
  /// exactly what must come off the tail of `rest`.
  ///
  /// **Only for the verbs that declare a body**, through [takesBody]. `run`
  /// hands its whole tail to a foreign program and reads `--` as one of that
  /// program's own words; subtracting a body there would take the caller's
  /// arguments away from the thing they were typed for. Which words are this
  /// verb's is a fact about the verb, and the base may not assume it.
  List<String> get positionals {
    final rest = argResults!.rest;
    if (!_takesBody) return rest;
    final trailing = body().length;
    return trailing == 0 ? rest : rest.sublist(0, rest.length - trailing);
  }

  /// Declares that this verb's command line ends in `-- <command>`: everything
  /// after the sentinel is somebody else's program, and none of it is a
  /// positional of this verb.
  void takesBody() => _takesBody = true;
  bool _takesBody = false;

  /// Declares that this verb's own positionals stop at [positionalLabels] and
  /// everything after them belongs to a foreign program — `run`'s function
  /// arguments, read with no `--` sentinel because the wrapped body's own
  /// argument grammar owns that word. The same kind of fact as [takesBody]:
  /// words that are not this verb's to count, arity-check, or judge.
  void takesTrailingArgs() => _takesTrailingArgs = true;
  bool _takesTrailingArgs = false;

  /// This verb's own positionals, in order, exactly as they read at the
  /// shell — `<coord>`, `<coord:path>`, `<event[,event]>`. **The single
  /// source both the invocation line and the arity refusal are derived
  /// from**, so a verb's grammar lives in one declaration and nowhere else:
  /// not in a dartdoc comment nobody reads at the terminal, and not
  /// hand-copied into a `usageException` that can drift from it.
  ///
  /// A label is a grammar fragment, not a bare word where the slot is not
  /// atomic — `read` declares `coord:path` because that is what the slot
  /// truly demands, and forcing every verb onto one-word labels would print
  /// a usage line that reads well and lies.
  List<String> get positionalLabels;

  /// This verb's own positionals, checked against [positionalLabels] and
  /// returned — or a usage refusal naming every one of them, in the verb's
  /// own words, built once here rather than by hand at each call site.
  ///
  /// **Calling this is what makes a short call safe further down.** A verb
  /// that read [coordinate] or indexed its own positionals without calling
  /// this first could pass on a call with too few words and crash on a raw
  /// index instead of refusing — which is exactly the shape the arity bug
  /// that opened this file took, one layer up.
  List<String> requirePositionals() {
    final words = positionals;
    final labels = positionalLabels;
    if (words.length < labels.length) {
      final verb = labels.length == 1 ? 'is' : 'are';
      usageException(
        '$name: ${labels.map((l) => '<$l>').join(' ')} $verb required',
      );
    }
    return words;
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

  /// The first positional read as a coordinate. Reads through
  /// [requirePositionals], so a verb that only declared one label and was
  /// then indexed for a second gets a usage refusal here rather than a raw
  /// index failure further down.
  Coordinate coordinate() {
    try {
      return Coordinate.parse(requirePositionals().first);
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
    final typed = requirePositionals().first;
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
