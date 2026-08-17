import 'package:args/command_runner.dart';

/// The grammar contract every verb of `mem` and `entity` states once, and
/// the one law that derives both the `--help` invocation line and the arity
/// refusal from it. Neither surface owns the other: this file sits beside
/// both, under `cli`, and each verb base class mixes it onto its own
/// `Command<void>`.
///
/// **The generalization.** `entity`'s original contract was `positionalLabels`
/// alone — every verb's arity fixed at the label count. `mem`'s was that plus
/// an optional floor (`health`, `refocus`, `tag`, `gist` accept zero) and a
/// repeating tail (`recall`, `walk` absorb any number of words at the last
/// label). The second is the strict superset: a fixed-arity verb is simply
/// `minPositionals == positionalLabels.length` with `repeating == false`,
/// which is this mixin's default — so every existing `entity` verb states
/// nothing new to keep its exact grammar. Even `run`, `entity`'s one
/// variable-tail verb, folds in as `minPositionals: 2, repeating: true`
/// rather than surviving as a case this contract cannot state.
///
/// **What stays additive, not folded.** [takesBody] and [takesTrailingArgs]
/// mark a verb's tail as somebody else's words — a foreign program's command
/// line or its own arguments — never this verb's positionals to arity-check.
/// They sit on top of the three grammar facts and subtract from what
/// [requirePositionals] counts; they are not a fourth way of stating arity.
base mixin PositionalGrammar on Command<void> {
  /// This verb's own positionals, in order, exactly as they read at the
  /// shell — `<coord>`, `<coord:path>`, `<topic>`. **The single source
  /// [invocation] and the arity refusal are both derived from**, so a verb's
  /// grammar lives in one declaration and nowhere else — not in a dartdoc
  /// comment nobody reads at the terminal, and not hand-copied into a
  /// `usageException` that can drift from it.
  ///
  /// A label is a grammar fragment, not a bare word where the slot is not
  /// atomic — `read` declares `coord:path` because that is what the slot
  /// truly demands. Empty by default: verbs that take no positional at all
  /// (`survey`) need not override it.
  List<String> get positionalLabels => const [];

  /// How many of [positionalLabels] must be present. Defaults to every
  /// label — the ordinary, fixed-arity case every `entity` verb and most of
  /// `mem`'s use. `mem`'s middle tier (`health`, `refocus`, `tag`, `gist`)
  /// overrides this to `0`: a verb that falls back to selector flags when
  /// the topic is bare has a positional that is genuinely optional, not a
  /// fact [positionalLabels] alone can express.
  int get minPositionals => positionalLabels.length;

  /// Whether the last label absorbs any number of words rather than exactly
  /// one — `recall <topic>...` and `walk <entry>...`. **No upper bound
  /// applies while this is true**; the ceiling [requirePositionals] enforces
  /// on every other verb is exactly the thing a repeating slot exists to
  /// remove. False by default, which is every `entity` verb and most of
  /// `mem`'s.
  bool get repeating => false;

  /// Declares that this verb's command line ends in `-- <command>`:
  /// everything after the sentinel is somebody else's program, and none of
  /// it is a positional of this verb. [positionals] subtracts the body's
  /// words before anything here counts arity.
  void takesBody() => _takesBody = true;
  bool _takesBody = false;

  /// Declares that this verb's own positionals stop at [positionalLabels]
  /// and everything after them belongs to a foreign program — `run`'s
  /// function arguments, read with no `--` sentinel because the wrapped
  /// body's own argument grammar owns that word. Words past the declared
  /// labels are not this verb's to count, arity-check, or judge.
  void takesTrailingArgs() => _takesTrailingArgs = true;
  bool _takesTrailingArgs = false;

  /// The words after `--`, taken from the raw argument list rather than
  /// [ArgResults.rest] — the parser folds both sides of the separator into
  /// one list, while the two halves mean different things: before it stand
  /// this verb's own positionals, after it stands somebody else's command
  /// line. Empty for every verb that never declared [takesBody].
  List<String> body() {
    final raw = argResults!.arguments;
    final at = raw.indexOf('--');
    return at < 0 ? const [] : raw.sublist(at + 1);
  }

  /// This verb's own positionals — [ArgResults.rest] with the body's words
  /// subtracted where [takesBody] applies. **Never one of somebody else's
  /// command line.** The parser folds both sides of `--` into `rest`, so an
  /// arity question asked of `rest` directly counts the body's words as if
  /// the caller had typed them — the exact shape of the bug that opened this
  /// contract (`entity act <coord> -- sh -c …` with the action omitted
  /// passed every guard and landed an act named `sh`).
  List<String> get positionals {
    final rest = argResults!.rest;
    if (!_takesBody) return rest;
    final trailing = body().length;
    return trailing == 0 ? rest : rest.sublist(0, rest.length - trailing);
  }

  /// This verb's own positionals, checked against [positionalLabels],
  /// [minPositionals] and [repeating], and returned — or a usage refusal
  /// naming every one of them, in the verb's own words, built once here
  /// rather than by hand at each call site.
  ///
  /// **Calling this is what makes a short call safe further down, and a
  /// long one refused instead of silently truncated or crashed on a raw
  /// index.**
  List<String> requirePositionals() {
    final words = positionals;
    final labels = positionalLabels;
    final min = minPositionals;
    if (words.length < min) {
      final missing = labels.sublist(0, min);
      final verb = missing.length == 1 ? 'is' : 'are';
      usageException(
        '$name: ${missing.map((l) => '<$l>').join(' ')} $verb required',
      );
    }
    if (!repeating && !_takesTrailingArgs && words.length > labels.length) {
      usageException(
        '$name: unexpected argument(s): '
        '${words.sublist(labels.length).join(' ')} — expected '
        '${labels.map((l) => '<$l>').join(' ')}',
      );
    }
    return words;
  }

  /// The single optional positional — `mem`'s `health`, `refocus`, `tag`,
  /// `gist` — read through [requirePositionals] so a second, uncounted word
  /// is refused rather than silently dropped, and null when the slot was
  /// left bare.
  String? optionalPositional() {
    final words = requirePositionals();
    return words.isEmpty ? null : words.first;
  }

  /// **The one-line grammar `--help` prints, derived from [positionalLabels],
  /// [minPositionals], [repeating], [takesBody] and [takesTrailingArgs] —
  /// nothing hand-written.** A label at or past [minPositionals] prints
  /// bracketed, since it is the caller's to omit; the last label repeats
  /// with `...` when [repeating] says so; a declared body or trailing-args
  /// marker follows every positional, since both are always the tail.
  @override
  String get invocation {
    final labels = positionalLabels;
    final min = minPositionals;
    final words = <String>[
      for (var i = 0; i < labels.length; i++)
        _bracket(
          '<${labels[i]}>${i == labels.length - 1 && repeating ? '...' : ''}',
          optional: i >= min,
        ),
      if (_takesBody) '-- <command>',
      if (_takesTrailingArgs) '[args...]',
    ];
    final prefix = '${runner!.executableName} $name';
    return words.isEmpty ? prefix : '$prefix ${words.join(' ')}';
  }

  String _bracket(String word, {required bool optional}) =>
      optional ? '[$word]' : word;
}
