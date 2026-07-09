import 'package:xml/xml.dart';

import 'edit_op.dart';

/// Raised when a legal-syntax op cannot apply to THIS atom's tree: adding an
/// element that already exists, setting/removing/renaming one that does not,
/// a handle-less op against a tag with named instances (the arity guard), or
/// the member-split case (body reached through an `<xi:include>`). Distinct
/// from [EditUsageException] (which is bad syntax): this is a well-formed op
/// meeting an incompatible document. Command → stderr, exit 1.
final class EditConflictException implements Exception {
  EditConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Applies a validated [EditOp] to a parsed atom DOM, in place. The pure heart
/// of the write-half — no IO, no serialization, no argv.
///
/// SCHEMA-BLIND. The flat genome has no realm containers and no compiled
/// vocabulary: particles are direct children of `<atom>`, tags are open, and
/// whether a tag is named vs bare is a fact of the DOCUMENT, not of a table.
/// So `apply` finds/adds/removes/renames `<tag [name=…]>` under the root, and
/// an attribute op writes the scalar on `<atom>` itself.
///
/// THE ARITY GUARD — the runtime replacement for the dead compiled arity table.
/// A handle-less op against a tag that has `name=` siblings is the commonest
/// agent typo (dropped handle) and MUST be exit-1, never silent corruption:
///   - `set`/`remove` without a handle when named same-tag elements exist →
///     conflict ("give a handle").
///   - `add` of a bare tag when named siblings exist → same conflict.
///
/// THE MEMBER-SPLIT GUARD (v1 scope cut, settled). An atom may split its body
/// across member files pulled in by `<xi:include>`. v1 `edit` operates on the
/// SINGLE source file the id resolves to — it does NOT follow includes. If the
/// root carries an `<xi:include>` and the target element is not literally
/// present, the truth may live in a member: raise [EditConflictException]
/// telling the caller to edit the member directly. Never silently act against
/// the wrong file.
///
/// THE OPERATIONS (apply, by verb):
///   add    — target must NOT already exist (named: no sibling with that
///            `name`; bare: no same-tag element) → append a new element to the
///            end of `<atom>` with the stdin content as its body, `name=` set
///            when a handle was given. Duplicate → conflict.
///   set    — upsert (create-or-replace): replace the body if the target
///            exists, create it (appended last) if not. This is the
///            schema-blind form of the old singleton add≡set convergence.
///            attribute: set the scalar on `<atom>`.
///   remove — element must exist → detach it. Absent → conflict.
///   rename — named element must exist; newName must NOT collide with a
///            sibling → rewrite its `name=` handle, body untouched. Absent or
///            collision → conflict.
///
/// ORDERING. A new element appends to the END of the root's children. Document
/// order is preserved for everything that already exists; the new node lands
/// last.
///
/// PURITY. Mutates the passed [XmlDocument] in place. Testable over a parsed
/// string with zero filesystem.
final class AtomEditor {
  const AtomEditor();

  /// Apply [op] to [doc] in place. Throws [EditConflictException] when the op
  /// is legal but the document cannot host it (duplicate, absent target,
  /// missing handle against named instances, member-split).
  void apply(XmlDocument doc, EditOp op) {
    final root = doc.rootElement;

    if (op.targetKind == TargetKind.attribute) {
      root.setAttribute(op.target, op.value!);
      return;
    }

    _guardArity(root, op);
    _guardMemberSplit(root, op);

    switch (op.verb) {
      case EditVerb.add:
        _add(root, op);
      case EditVerb.set:
        _set(root, op);
      case EditVerb.remove:
        _remove(root, op);
      case EditVerb.rename:
        _rename(root, op);
    }
  }

  /// The arity guard: a handle-less op against a tag that has named instances
  /// is a dropped handle, not an intent to act on a bare element.
  void _guardArity(XmlElement root, EditOp op) {
    if (op.name != null) return;
    final hasNamed = root.childElements.any(
      (e) => e.name.local == op.target && e.getAttribute('name') != null,
    );
    if (hasNamed) {
      throw EditConflictException(
        "'${op.target}' has named instances; give a handle",
      );
    }
  }

  /// The member-split guard: an xi:include beside an absent target means the
  /// truth may live in a member file — refuse rather than act on the wrong one.
  void _guardMemberSplit(XmlElement root, EditOp op) {
    if (_find(root, op.target, op.name) != null) return;
    const xiNs = 'http://www.w3.org/2001/XInclude';
    final hasInclude = root.childElements.any(
      (e) => e.name.local == 'include' && e.name.namespaceUri == xiNs,
    );
    if (hasInclude) {
      throw EditConflictException(
        "'${op.target}' not in this file and it has xi:include members; "
        'edit the member file directly',
      );
    }
  }

  void _add(XmlElement root, EditOp op) {
    if (_find(root, op.target, op.name) != null) {
      throw EditConflictException(
        op.name == null
            ? "'${op.target}' already exists (use set to replace)"
            : "'${op.target}' named '${op.name}' already exists (use set to replace)",
      );
    }
    root.children.add(_newElement(op));
  }

  void _set(XmlElement root, EditOp op) {
    final el = _find(root, op.target, op.name);
    if (el == null) {
      root.children.add(_newElement(op));
      return;
    }
    el.children
      ..clear()
      ..add(XmlText(op.content!));
  }

  void _remove(XmlElement root, EditOp op) {
    final el = _find(root, op.target, op.name);
    if (el == null) {
      throw EditConflictException(_absent(op));
    }
    el.remove();
  }

  void _rename(XmlElement root, EditOp op) {
    final el = _find(root, op.target, op.name);
    if (el == null) {
      throw EditConflictException(_absent(op));
    }
    if (_find(root, op.target, op.newName) != null) {
      throw EditConflictException(
        "'${op.target}' named '${op.newName}' already exists",
      );
    }
    el.setAttribute('name', op.newName!);
  }

  XmlElement _newElement(EditOp op) {
    final el = XmlElement(XmlName(op.target));
    if (op.name != null) el.setAttribute('name', op.name!);
    el.children.add(XmlText(op.content!));
    return el;
  }

  String _absent(EditOp op) => op.name == null
      ? "'${op.target}' not found"
      : "'${op.target}' named '${op.name}' not found";

  /// Find a direct child `<tag>` of [root]; with [name], the one whose `name=`
  /// matches; without, the bare one (no `name=` attribute).
  XmlElement? _find(XmlElement root, String tag, [String? name]) {
    for (final e in root.childElements) {
      if (e.name.local != tag) continue;
      final handle = e.getAttribute('name');
      if (name == null ? handle == null : handle == name) return e;
    }
    return null;
  }
}
