import 'particle.dart';

/// The four mutation verbs of `edit`. The grammar is `--<verb>-<target>`, the
/// verb fused with the particle/attribute it acts on (`--add-trait`,
/// `--set-v`, `--remove-antipattern`, `--rename-principle`). The vocabulary IS
/// the option surface; `--help` enumerates the cross-product.
enum EditVerb { add, set, remove, rename }

/// What an op targets — a prose particle or an atom attribute. The two differ in
/// where their payload rides: a particle's body arrives on STDIN; an attribute's
/// value rides ARGV. The parser resolves this from the target name alone.
enum TargetKind { particle, attribute }

/// A fully-parsed, validated edit operation — the structured form of one
/// `manifest edit` invocation, ready for [AtomEditor] to apply. Pure value type;
/// holds no IO.
///
/// Field meanings by verb (see [EditOpParser] for how argv/stdin map in):
///   add    — [name] required (named particle) or absent (singleton); [content]
///            from stdin is the body.
///   set    — particle: [name] addresses it, [content] is the new body.
///            attribute: [name] is the attr, [value] (argv) is the new scalar.
///   remove — [name] addresses the particle; no content.
///   rename — [name] is the current handle, [newName] the replacement; no content.
final class EditOp {
  const EditOp({
    required this.verb,
    required this.targetKind,
    required this.target,
    this.name,
    this.newName,
    this.content,
    this.value,
  });

  final EditVerb verb;
  final TargetKind targetKind;

  /// The particle or attribute name (e.g. `trait`, `v`) — the thing the verb acts on.
  final String target;

  /// The handle of the specific element (named particles), null for singletons/attrs.
  final String? name;

  /// The new handle, for [EditVerb.rename] only.
  final String? newName;

  /// The prose body from stdin, for particle add/set.
  final String? content;

  /// The scalar value from argv, for attribute set.
  final String? value;
}

/// Raised when an invocation cannot be parsed into a legal [EditOp]: malformed
/// flag, unknown verb, unknown particle, a v2-deferred relation particle, a realm
/// or arity mismatch, or a missing/extra argument. Carries a message the command
/// writes to stderr before exit 1.
final class EditUsageException implements Exception {
  EditUsageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses the raw argv tail of `manifest edit <id> …` into an [EditOp].
///
/// THE GRAMMAR (one op flag + positional handles; body on stdin):
///   `manifest edit <id> --<verb>-<target> [name [newName]] [--dry-run]`
///
/// RESPONSIBILITY SPLIT. This parser owns the SYNTAX→intent translation and all
/// validation that needs only the vocabulary ([particle.dart]); it touches no
/// filesystem and no DOM. The command layer ([EditCommand]) supplies the already-
/// resolved id, the stdin content, and the `--dry-run` flag separately.
///
/// THE ALGORITHM (parse):
///   1. Find the single op token of the form `--<verb>-<rest>`. Exactly one is
///      required — zero or many is a usage error.
///   2. Split on the FIRST `-` after `--`: `add` | `set` | `remove` | `rename`.
///      The remainder is the target name (`trait`, `v`, `antipattern`…). An
///      unknown verb is a usage error. Note the target may itself contain `-`
///      (none today, but `--rename-anti-pattern` must not mis-split) — split the
///      VERB off the front against the known verb set, not naively on every `-`.
///   3. Classify the target:
///        - in [editableAttrs]      → TargetKind.attribute
///        - in [editableParticles]  → TargetKind.particle (carry its spec)
///        - in [v2RelationParticles]→ usage error: "`<name>` editing is v2, not v1"
///        - else                    → usage error: "unknown particle/attribute"
///   4. Bind positionals + content against the (verb, target) shape, validating
///      arity. The matrix the implementation must enforce:
///
///      | verb   | particle (named)        | particle (singleton)  | attribute        |
///      |--------|-------------------------|-----------------------|------------------|
///      | add    | name=argv, content=stdin| content=stdin, no name| (n/a — error)    |
///      | set    | name=argv, content=stdin| content=stdin, no name| value=argv,no in |
///      | remove | name=argv               | no name               | (n/a — error)    |
///      | rename | name+newName=argv       | (n/a — no handle)     | (n/a — error)    |
///
///      Violations are usage errors: a name given for a singleton, a name missing
///      for a named particle, `rename`/`add`/`remove` on an attribute, content
///      piped to `remove`/`rename`, etc. (Whether stdin is present is told to the
///      parser by the command; the parser decides if that is legal for the shape.)
///
/// DESIGN NOTES (settled):
///   - SINGLETONS converge add≡set: there is one essence, so "add" and "set" both
///     mean create-or-replace. Accept both; `--rename-essence` is a usage error
///     (no handle to rename).
///   - The parser NEVER reads realm from argv — realm is the particle's, looked up,
///     never an input. There is no `--realm` flag to parse, by construction.
final class EditOpParser {
  const EditOpParser();

  /// Parse [args] (the tokens after `<id>`, with `--dry-run` already stripped by
  /// the command) plus whether [stdinPresent], into a validated [EditOp].
  /// Throws [EditUsageException] on any malformed or illegal invocation.
  EditOp parse(List<String> args, {required bool stdinPresent}) {
    final opFlags = args.where((a) => a.startsWith('--')).toList();
    final positionals = args.where((a) => !a.startsWith('--')).toList();

    if (opFlags.isEmpty) {
      throw EditUsageException('no op flag given; expected --<verb>-<target>');
    }
    if (opFlags.length > 1) {
      throw EditUsageException('only one op flag allowed; got ${opFlags.join(', ')}');
    }

    final flag = opFlags.first;
    final rest = flag.substring(2); // strip '--'

    EditVerb? verb;
    String target = '';
    for (final v in EditVerb.values) {
      final prefix = '${v.name}-';
      if (rest.startsWith(prefix)) {
        verb = v;
        target = rest.substring(prefix.length);
        break;
      }
    }
    if (verb == null) {
      final dashIdx = rest.indexOf('-');
      final verbName = dashIdx >= 0 ? rest.substring(0, dashIdx) : rest;
      throw EditUsageException(
          "unknown verb '$verbName'; expected: add, set, remove, rename");
    }
    if (target.isEmpty) {
      throw EditUsageException("missing target in '$flag'");
    }

    // Classify target
    TargetKind targetKind;
    ParticleSpec? spec;

    if (editableAttrs.contains(target)) {
      targetKind = TargetKind.attribute;
    } else if (v2RelationParticles.contains(target)) {
      throw EditUsageException(
          "'$target' editing is deferred to v2 — not available in v1.\n"
          "  v1 particles: ${editableParticles.keys.join(', ')}");
    } else {
      spec = lookupParticle(target);
      if (spec == null) {
        final valid = [...editableParticles.keys, ...editableAttrs]..sort();
        throw EditUsageException(
            "unknown particle or attribute '$target'.\n"
            "  Valid targets: ${valid.join(', ')}");
      }
      targetKind = TargetKind.particle;
    }

    // Attribute branch
    if (targetKind == TargetKind.attribute) {
      if (verb != EditVerb.set) {
        throw EditUsageException("'$flag': only --set-<attr> is valid for attributes");
      }
      if (positionals.isEmpty) {
        throw EditUsageException("'$flag': attribute value required on argv");
      }
      if (positionals.length > 1) {
        throw EditUsageException("'$flag': too many arguments");
      }
      if (stdinPresent) {
        throw EditUsageException("'$flag': attribute set takes its value from argv, not stdin");
      }
      return EditOp(verb: verb, targetKind: targetKind, target: target, value: positionals.first);
    }

    // Particle branch
    final isSingleton = spec!.arity == Arity.singleton;

    if (isSingleton) {
      if (verb == EditVerb.rename) {
        throw EditUsageException("'$flag': '$target' is a singleton — no handle to rename");
      }
      if (positionals.isNotEmpty) {
        throw EditUsageException("'$flag': '$target' is a singleton — no name expected");
      }
      if (verb == EditVerb.remove) {
        if (stdinPresent) {
          throw EditUsageException("'$flag': remove does not take a body on stdin");
        }
        return EditOp(verb: verb, targetKind: targetKind, target: target);
      }
      // add or set (converge for singletons)
      if (!stdinPresent) {
        throw EditUsageException("'$flag': body required on stdin");
      }
      return EditOp(verb: verb, targetKind: targetKind, target: target);
    }

    // Named particle
    if (verb == EditVerb.add || verb == EditVerb.set) {
      if (positionals.isEmpty) {
        throw EditUsageException(
            "'$flag': name required.\n"
            "  Usage: manifest edit <id> $flag <name>  (body on stdin)");
      }
      if (positionals.length > 1) {
        throw EditUsageException("'$flag': too many arguments");
      }
      if (!stdinPresent) {
        throw EditUsageException("'$flag': body required on stdin");
      }
      return EditOp(verb: verb, targetKind: targetKind, target: target, name: positionals.first);
    }

    if (verb == EditVerb.remove) {
      if (positionals.isEmpty) {
        throw EditUsageException(
            "'$flag': name required.\n"
            "  Usage: manifest edit <id> $flag <name>");
      }
      if (positionals.length > 1) {
        throw EditUsageException("'$flag': too many arguments");
      }
      if (stdinPresent) {
        throw EditUsageException("'$flag': remove does not take a body on stdin");
      }
      return EditOp(verb: verb, targetKind: targetKind, target: target, name: positionals.first);
    }

    // rename
    if (positionals.length < 2) {
      throw EditUsageException(
          "'$flag': rename requires two names.\n"
          "  Usage: manifest edit <id> $flag <name> <new-name>");
    }
    if (positionals.length > 2) {
      throw EditUsageException("'$flag': too many arguments");
    }
    if (stdinPresent) {
      throw EditUsageException("'$flag': rename does not take a body on stdin");
    }
    return EditOp(
      verb: verb,
      targetKind: targetKind,
      target: target,
      name: positionals.first,
      newName: positionals[1],
    );
  }
}
