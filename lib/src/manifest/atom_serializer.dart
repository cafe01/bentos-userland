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
/// SCHEMA-BLIND. The flat genome's canonical attrs are `id` + `v`, both on
/// `<atom>`, both survive untouched — there is no legacy-canonicalization pass,
/// because there is no schema to canonicalize to. Whatever attributes and tags
/// the document carries, it keeps.
///
/// WHY IT EXISTS — IDEMPOTENCY IS THE CONTRACT. Because `manifest` is the SOLE
/// author of atoms, there is no foreign formatting to preserve: the canonical
/// format simply IS this serializer's output. The one law every edit stands on:
///
///     serialize(parse(x)) == x      for any x this serializer has ever emitted
///
/// So a NO-OP edit produces a byte-identical file, and a real edit produces a
/// diff touching ONLY the changed element — never an incidental reflow of the
/// rest. This is what makes `edit` safe for a bulk faculty pass: every cut is
/// visible, nothing else moves.
///
/// WHITESPACE. Prose bodies' newlines and indentation are CONTENT, not
/// formatting — and schema-blind means no hardcoded tag set decides which
/// bodies count (a bare tag list is the same strong-typing disease as the dead
/// vocabulary). The rule is structural: every LEAF element with text content
/// keeps its inner whitespace verbatim; container elements pretty-print with
/// the tree's 2-space indent.
///
/// PURE. No IO; takes a parsed document, returns a string. The command owns
/// read and write.
String serializeAtom(XmlDocument doc) {
  return doc.toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: _isProseLeaf,
  );
}

/// A leaf element whose children are text — its whitespace is prose content.
bool _isProseLeaf(XmlNode node) =>
    node is XmlElement &&
    node.childElements.isEmpty &&
    node.innerText.isNotEmpty;
