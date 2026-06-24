import 'package:xml/xml.dart';

import 'edit_op.dart';
import 'particle.dart';

/// Raised when a legal-syntax op cannot apply to THIS atom's tree: adding a
/// particle that already exists, setting/removing/renaming one that does not, or
/// the member-split case (target realm reached only through an `<xi:include>`).
/// Distinct from [EditUsageException] (which is bad syntax): this is a
/// well-formed op meeting an incompatible document. Command → stderr, exit 1.
final class EditConflictException implements Exception {
  EditConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Applies a validated [EditOp] to a parsed atom DOM, in place. The pure heart of
/// the write-half — no IO, no serialization, no argv. Mirrors [ComposeEngine]'s
/// role for the read-half: the command is thin, this is the logic.
///
/// THE REALM LAW (Standard Model §V) made mechanical. Every particle inhabits
/// exactly one realm; [editableParticles] carries it. So `apply` NEVER asks the
/// caller where an edit lands — it reads the particle's realm, finds the matching
/// container (`<living-abstract>` / `<living-concrete>`), and acts there. An atom
/// attribute (`v`) lives on the `<atom>` root itself.
///
/// CONTAINER RESOLUTION:
///   - The atom root is the document's outermost element (`<atom>`; legacy files
///     may carry `id`/`v`/`desc` attributes — leave foreign attrs for the
///     serializer's canonicalization to handle, do not edit them here unless the
///     op targets one).
///   - For a particle op, locate the realm container under the root. If it is
///     ABSENT, `add`/`set` CREATE it (an atom may have no concrete yet); but
///     `remove`/`rename`/`set`-of-an-absent-particle in an absent container is a
///     conflict.
///
/// THE MEMBER-SPLIT GUARD (v1 scope cut, settled). An atom may split its body
/// across member files (`alfred_abstract.xml` pulled in by `<xi:include>` beside
/// the package root). v1 `edit` operates on the SINGLE source file the id
/// resolves to — it does NOT follow includes to mutate a member. So: if the
/// target realm container is not present as a literal child but an
/// `<xi:include>` is, raise [EditConflictException] naming the member to edit
/// directly ("trait lives behind an include; edit faculty/x/x_abstract.xml").
/// Never silently succeed against the wrong file. (Following includes is a v2
/// extension; the single-file form is every live faculty/soul today.)
///
/// THE OPERATIONS (apply, by verb):
///   add    — particle must NOT already exist (named: no sibling with that
///            `name`; singleton: none present) → append a new element to the
///            realm container with the stdin content as its body, `name=` set for
///            named particles. Duplicate → conflict.
///   set    — particle: element must exist → replace its body with content,
///            preserve its `name`. Singleton add≡set (create-or-replace).
///            attribute: set the scalar on `<atom>` (e.g. `v`).
///            Absent target → conflict (except singleton, which set creates).
///   remove — element must exist → detach it. Absent → conflict.
///   rename — named particle must exist; newName must NOT collide with a sibling
///            → rewrite its `name=` handle, body untouched. Absent or collision
///            → conflict.
///
/// ORDERING. A new element appends to the END of its realm container. v1 makes no
/// promise about grouping siblings by type (traits-together, principles-together);
/// document order is preserved for everything that already exists, and the new
/// node lands last. (If the bulk faculty pass later wants typed grouping, that is
/// a separate, additive concern — do not over-build it here.)
///
/// PURITY. Mutates the passed [XmlDocument] and returns it (or void — author's
/// call, but keep it side-effect-on-the-arg, no IO). Testable over a parsed
/// string with zero filesystem.
final class AtomEditor {
  const AtomEditor();

  /// Apply [op] to [doc] in place. Throws [EditConflictException] when the op is
  /// legal but the document cannot host it (duplicate, absent target, member-split).
  void apply(XmlDocument doc, EditOp op) {
    final root = doc.rootElement;

    if (op.targetKind == TargetKind.attribute) {
      root.setAttribute(op.target, op.value!);
      return;
    }

    final spec = lookupParticle(op.target)!;
    final containerName =
        spec.realm == Realm.abstract_ ? 'living-abstract' : 'living-concrete';
    var container = root.getElement(containerName);

    if (container == null) {
      // Member-split guard: a realm reached only through xi:include
      const xiNs = 'http://www.w3.org/2001/XInclude';
      final hasInclude = root.childElements.any(
        (e) => e.name.local == 'include' && e.name.namespaceUri == xiNs,
      );
      if (hasInclude) {
        throw EditConflictException(
          "'${op.target}' lives behind an xi:include; "
          'edit the member file directly',
        );
      }
      if (op.verb == EditVerb.add ||
          (op.verb == EditVerb.set && spec.arity == Arity.singleton)) {
        // Create the container so the op can proceed
        final newContainer = XmlElement(XmlName(containerName));
        root.children.add(newContainer);
        container = newContainer;
      } else {
        throw EditConflictException(
          "'$containerName' is absent; cannot ${op.verb.name} '${op.target}'",
        );
      }
    }

    switch (op.verb) {
      case EditVerb.add:
        _add(container, op, spec);
      case EditVerb.set:
        _set(container, op, spec);
      case EditVerb.remove:
        _remove(container, op);
      case EditVerb.rename:
        _rename(container, op);
    }
  }

  void _add(XmlElement container, EditOp op, ParticleSpec spec) {
    if (spec.arity == Arity.singleton) {
      if (_find(container, op.target) != null) {
        throw EditConflictException("'${op.target}' singleton already exists");
      }
      final el = XmlElement(XmlName(op.target))..children.add(XmlText(op.content!));
      container.children.add(el);
    } else {
      if (_find(container, op.target, op.name) != null) {
        throw EditConflictException(
          "'${op.target}' named '${op.name}' already exists",
        );
      }
      final el = XmlElement(XmlName(op.target))
        ..setAttribute('name', op.name!)
        ..children.add(XmlText(op.content!));
      container.children.add(el);
    }
  }

  void _set(XmlElement container, EditOp op, ParticleSpec spec) {
    if (spec.arity == Arity.singleton) {
      var el = _find(container, op.target);
      if (el == null) {
        el = XmlElement(XmlName(op.target));
        container.children.add(el);
      }
      el.children
        ..clear()
        ..add(XmlText(op.content!));
    } else {
      final el = _find(container, op.target, op.name);
      if (el == null) {
        throw EditConflictException(
          "'${op.target}' named '${op.name}' not found",
        );
      }
      el.children
        ..clear()
        ..add(XmlText(op.content!));
    }
  }

  void _remove(XmlElement container, EditOp op) {
    final el = _find(container, op.target, op.name);
    if (el == null) {
      throw EditConflictException("'${op.target}' named '${op.name}' not found");
    }
    el.remove();
  }

  void _rename(XmlElement container, EditOp op) {
    final el = _find(container, op.target, op.name);
    if (el == null) {
      throw EditConflictException("'${op.target}' named '${op.name}' not found");
    }
    if (_find(container, op.target, op.newName) != null) {
      throw EditConflictException(
        "'${op.target}' named '${op.newName}' already exists",
      );
    }
    el.setAttribute('name', op.newName!);
  }

  XmlElement? _find(XmlElement container, String tag, [String? name]) {
    for (final e in container.childElements) {
      if (e.name.local == tag &&
          (name == null || e.getAttribute('name') == name)) {
        return e;
      }
    }
    return null;
  }
}
