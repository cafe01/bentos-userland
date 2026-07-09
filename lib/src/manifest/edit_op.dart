/// The four mutation verbs of `edit`. The grammar is positional, git-style:
/// `manifest edit <id> <verb> <selector> [handles…]` — the verb is a word, not a
/// flag. The verb set is closed; the selector vocabulary is OPEN (schema-blind).
enum EditVerb { add, set, remove, rename }

/// What an op targets — an element or an atom attribute. The selector's sigil
/// decides: `@x` is the attribute `x` (xpath-flavored), a bare token is an
/// element tag. The two differ in where their payload rides: an element's body
/// arrives on STDIN; an attribute's value rides ARGV.
enum TargetKind { element, attribute }

/// A fully-parsed, validated edit operation — the structured form of one
/// `manifest edit` invocation, ready for [AtomEditor] to apply. Pure value type;
/// holds no IO.
///
/// Field meanings by verb (see [EditOpParser] for how argv/stdin map in):
///   add    — [name] optional handle (named element) or absent (bare element);
///            [content] from stdin is the body.
///   set    — element: optional [name] addresses it, [content] is the new body.
///            attribute: [target] is the attr, [value] (argv) is the new scalar.
///   remove — element only; optional [name]; no content.
///   rename — element only; [name] is the current handle, [newName] the
///            replacement; no content.
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

  /// The element tag or attribute name (e.g. `capacity`, `v`) — the thing the
  /// verb acts on. Any string: the vocabulary is the document's, not ours.
  final String target;

  /// The handle of the specific element (`name=` attribute); null for bare
  /// elements and attributes.
  final String? name;

  /// The new handle, for [EditVerb.rename] only.
  final String? newName;

  /// The prose body from stdin, for element add/set.
  final String? content;

  /// The scalar value from argv, for attribute set.
  final String? value;
}

/// Raised when an invocation cannot be parsed into a legal [EditOp]: unknown
/// verb, missing selector, wrong positional arity for the verb, or a stdin/argv
/// payload mismatch. Carries a message the command writes to stderr before
/// exit 1.
final class EditUsageException implements Exception {
  EditUsageException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses the op tail of `manifest edit <id> …` into an [EditOp].
///
/// THE GRAMMAR (pure position; `--dry-run` is stripped by the command):
///   `manifest edit <id> <verb> <selector> [handles…]`
///
///   verb      — one of add · set · remove · rename (closed set, argv word).
///   selector  — `@x` targets the attribute `x` on `<atom>`; any other token is
///               an element tag under `<atom>`. Schema-blind: no vocabulary, no
///               realm, no arity table — the document is the schema.
///   handles   — bound by verb:
///
///      | verb   | element                       | attribute (`@x`)    |
///      |--------|-------------------------------|---------------------|
///      | add    | [name]; body=stdin            | (n/a — error)       |
///      | set    | [name]; body=stdin            | value=argv, no stdin|
///      | remove | [name]; no stdin              | (n/a — error)       |
///      | rename | name newName; no stdin        | (n/a — deferred)    |
///
/// Whether the element is named vs bare is a runtime fact — was a handle given?
/// The DOM-level safety net for a FORGOTTEN handle (same-tag named siblings
/// exist) lives in [AtomEditor], which sees the document; this parser sees only
/// argv+stdin and validates shape.
///
/// RESPONSIBILITY SPLIT. This parser owns the SYNTAX→intent translation; it
/// touches no filesystem and no DOM. The command layer ([EditCommand]) supplies
/// the already-resolved id, the stdin content, and `--dry-run` separately.
final class EditOpParser {
  const EditOpParser();

  /// Parse [args] (the tokens after `<id>`, with `--dry-run` already stripped by
  /// the command) plus whether [stdinPresent], into a validated [EditOp].
  /// Throws [EditUsageException] on any malformed or illegal invocation.
  EditOp parse(List<String> args, {required bool stdinPresent}) {
    if (args.isEmpty) {
      throw EditUsageException(
          'verb required; expected: add, set, remove, rename');
    }
    final verbWord = args.first;
    final verb = EditVerb.values
        .cast<EditVerb?>()
        .firstWhere((v) => v!.name == verbWord, orElse: () => null);
    if (verb == null) {
      throw EditUsageException(
          "unknown verb '$verbWord'; expected: add, set, remove, rename");
    }

    if (args.length < 2) {
      throw EditUsageException(
          '$verbWord: selector required (an element tag, or @attr)');
    }
    final selector = args[1];
    final tail = args.sublist(2);

    // Attribute branch — `@x` sigil (element names can never start with `@`).
    if (selector.startsWith('@')) {
      final attr = selector.substring(1);
      if (attr.isEmpty) {
        throw EditUsageException("'@': attribute name required after '@'");
      }
      if (verb != EditVerb.set) {
        throw EditUsageException(
            "$verbWord $selector: only 'set' is valid for attributes");
      }
      if (tail.isEmpty) {
        throw EditUsageException(
            'set $selector: attribute value required on argv');
      }
      if (tail.length > 1) {
        throw EditUsageException('set $selector: too many arguments');
      }
      if (stdinPresent) {
        throw EditUsageException(
            'set $selector: attribute value rides argv, not stdin');
      }
      return EditOp(
        verb: verb,
        targetKind: TargetKind.attribute,
        target: attr,
        value: tail.first,
      );
    }

    // Element branch.
    switch (verb) {
      case EditVerb.add:
      case EditVerb.set:
        if (tail.length > 1) {
          throw EditUsageException('$verbWord $selector: too many arguments');
        }
        if (!stdinPresent) {
          throw EditUsageException('$verbWord $selector: body required on stdin');
        }
        return EditOp(
          verb: verb,
          targetKind: TargetKind.element,
          target: selector,
          name: tail.isEmpty ? null : tail.first,
        );
      case EditVerb.remove:
        if (tail.length > 1) {
          throw EditUsageException('remove $selector: too many arguments');
        }
        if (stdinPresent) {
          throw EditUsageException(
              'remove $selector: remove does not take a body on stdin');
        }
        return EditOp(
          verb: verb,
          targetKind: TargetKind.element,
          target: selector,
          name: tail.isEmpty ? null : tail.first,
        );
      case EditVerb.rename:
        if (tail.length < 2) {
          throw EditUsageException(
              'rename $selector: two handles required.\n'
              '  Usage: manifest edit <id> rename $selector <name> <new-name>');
        }
        if (tail.length > 2) {
          throw EditUsageException('rename $selector: too many arguments');
        }
        if (stdinPresent) {
          throw EditUsageException(
              'rename $selector: rename does not take a body on stdin');
        }
        return EditOp(
          verb: verb,
          targetKind: TargetKind.element,
          target: selector,
          name: tail.first,
          newName: tail[1],
        );
    }
  }
}
