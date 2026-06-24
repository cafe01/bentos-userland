import 'package:xml/xml.dart';

/// Serialize an atom's SOURCE document back to its canonical on-disk form.
///
/// This is the sibling of [serializeComposed] (compose_engine.dart) but for the
/// WRITE path, and the difference is the whole point:
///   - `serializeComposed` flattens a COMPOSED being for loading — it strips the
///     now-dead `xmlns:xi` declarations because every include was spliced out.
///   - `serializeAtom` rewrites a SOURCE atom in place — `<xi:include>` nodes and
///     their namespace MUST survive untouched; a member-split atom still points at
///     its members after an edit. Strip nothing structural.
///
/// WHY IT EXISTS — IDEMPOTENCY IS THE CONTRACT (ticket #45 §4). Because `manifest`
/// is the SOLE author of atoms, there is no foreign formatting to preserve: the
/// canonical format simply IS this serializer's output. The one law every edit
/// stands on:
///
///     serialize(parse(x)) == x      for any x this serializer has ever emitted
///
/// So a NO-OP edit produces a byte-identical file, and a real edit produces a diff
/// touching ONLY the changed particle — never an incidental reflow of the rest.
/// This is what makes `edit` safe for a bulk faculty pass: every cut is visible,
/// nothing else moves. Hand-authored legacy atoms (today's tree — `id`/`origin`/
/// `desc` on `<atom>`, `v`/`updated` on the realms) are CANONICALIZED on first
/// touch: one desirable diff that brings them to the pure form (Standard Model
/// §VI), stable forever after.
///
/// IMPLEMENTATION CONSTRAINTS the author must meet:
///   - Pretty-print with the same 2-space indent the tree already uses, so the
///     first canonicalizing diff is minimal and human-readable.
///   - Preserve internal whitespace of the prose-bodied particles exactly as
///     `serializeComposed` does (its `_preservedElements` set — essence, purpose,
///     trait?, capacity, protocol, principle, knowledge, pattern, antipattern,
///     genesis): their newlines and indentation are CONTENT, not formatting.
///   - The fixed point must hold on REAL atoms, not just synthetic ones — the
///     proving test reads an actual tree file (see edit_roundtrip_test). Units
///     over MemoryFileSystem hide serialization drift (smoke-test-catches-what-
///     fake-device-cannot): the idempotency test MUST round-trip a real file.
///
/// PURE. No IO; takes a parsed document, returns a string. The command owns read
/// and write.
const _preservedElements = {
  'essence', 'purpose', 'trait',
  'capacity', 'protocol',
  'principle',
  'knowledge', 'pattern', 'antipattern',
  'genesis',
};

// Legacy attrs that live on <atom> in the old tree — stripped on first touch.
const _legacyAtomAttrs = {'id', 'origin', 'desc', 'created'};

// Legacy attrs that live on <living-abstract> / <living-concrete> — stripped on first touch.
const _legacyRealmAttrs = {'v', 'updated'};

const _realmElements = {'living-abstract', 'living-concrete'};

String serializeAtom(XmlDocument doc) {
  _canonicalizeLegacy(doc.rootElement);
  return doc.toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: (node) =>
        node is XmlElement && _preservedElements.contains(node.name.local),
  );
}

void _canonicalizeLegacy(XmlElement root) {
  root.attributes.removeWhere((a) => _legacyAtomAttrs.contains(a.name.local));
  for (final child in root.childElements) {
    if (_realmElements.contains(child.name.local)) {
      child.attributes.removeWhere((a) => _legacyRealmAttrs.contains(a.name.local));
    }
  }
}
