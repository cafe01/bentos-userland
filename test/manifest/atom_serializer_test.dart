import 'package:bentos_userland/src/manifest/atom_serializer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — the source serializer is a FIXED POINT:
/// `serialize(parse(x)) == x` for any x it has emitted. This is the whole safety
/// guarantee of `edit` — a no-op rewrites byte-identically, a real edit moves only
/// the touched element. Schema-blind: no canonicalization pass, no tag tables —
/// `id`/`v` and every other attribute survive untouched, and prose whitespace is
/// preserved structurally (every leaf element with text), not by tag name.
void main() {
  group('idempotency — the fixed point', () {
    test('flat-atom output round-trips byte-identically', () {
      const source = '<atom id="x.faculty" v="0.2">'
          '<telos>to remain one person</telos>'
          '<capacity name="recollection">gather yourself</capacity>'
          '</atom>';
      final once = serializeAtom(XmlDocument.parse(source));
      final twice = serializeAtom(XmlDocument.parse(once));
      expect(twice, once, reason: 'serialize must be a fixed point on its own output');
    });
  });

  group('canonical attrs survive — no legacy stripping', () {
    test('id and v on <atom> are kept verbatim', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom id="anamnesis.faculty" v="0.2"><telos>t</telos></atom>',
      ));
      expect(out, contains('id="anamnesis.faculty"'));
      expect(out, contains('v="0.2"'));
    });

    test('unknown attributes are kept too — the serializer is schema-blind', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom id="x.soul" v="1.0" origin="Cafe"><telos>t</telos></atom>',
      ));
      expect(out, contains('origin="Cafe"'));
      expect(serializeAtom(XmlDocument.parse(out)), out);
    });
  });

  group('prose whitespace is CONTENT, preserved for ANY leaf element', () {
    test('multi-line body keeps its newlines and indentation, tag unheard-of', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom id="x" v="1.0">'
        '<ritual name="wake">\n  Step A.\n  Step B.\n</ritual>'
        '</atom>',
      ));
      expect(out, contains('\n  Step A.\n  Step B.\n'));
      // …and it survives a re-parse unchanged.
      expect(serializeAtom(XmlDocument.parse(out)), out);
    });
  });

  group('source structure survives — this is NOT serializeComposed', () {
    test('xi:include nodes are NOT stripped (member-split atoms stay linked)', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom xmlns:xi="http://www.w3.org/2001/XInclude" id="x.faculty" v="1.0">'
        '<xi:include href="x_abstract.xml"/>'
        '</atom>',
      ));
      expect(out, contains('x_abstract.xml'));
      expect(serializeAtom(XmlDocument.parse(out)), out);
    });
  });
}
