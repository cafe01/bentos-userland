import 'package:bentos_userland/src/manifest/atom_serializer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// CONTRACT — the source serializer is a FIXED POINT (ticket #45 §4):
/// `serialize(parse(x)) == x` for any x it has emitted. This is the whole safety
/// guarantee of `edit` — a no-op rewrites byte-identically, a real edit moves only
/// the touched particle. Unlike `serializeComposed`, it preserves `<xi:include>`.
void main() {
  group('idempotency — the fixed point', () {
    test('canonical output round-trips byte-identically (two-pass stability)', () {
      // Whatever the canonical form of this atom is, serializing it a SECOND time
      // must change nothing. (First pass canonicalizes; from then on, stable.)
      const source = '<atom v="1.0">'
          '<living-abstract>'
          '<essence>e</essence>'
          '<trait name="refined">form matters</trait>'
          '</living-abstract>'
          '</atom>';
      final once = serializeAtom(XmlDocument.parse(source));
      final twice = serializeAtom(XmlDocument.parse(once));
      expect(twice, once, reason: 'serialize must be a fixed point on its own output');
    });
  });

  group('prose-particle whitespace is CONTENT, preserved verbatim', () {
    test('multi-line protocol body keeps its newlines and indentation', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom v="1.0"><living-concrete>'
        '<protocol name="wake">\n  Step A.\n  Step B.\n</protocol>'
        '</living-concrete></atom>',
      ));
      expect(out, contains('\n  Step A.\n  Step B.\n'));
      // …and it survives a re-parse unchanged.
      expect(serializeAtom(XmlDocument.parse(out)), out);
    });
  });

  group('source structure survives — this is NOT serializeComposed', () {
    test('xi:include nodes are NOT stripped (member-split atoms stay linked)', () {
      final out = serializeAtom(XmlDocument.parse(
        '<atom xmlns:xi="http://www.w3.org/2001/XInclude" v="1.0">'
        '<xi:include href="x_abstract.xml"/>'
        '</atom>',
      ));
      expect(out, contains('x_abstract.xml'));
      expect(serializeAtom(XmlDocument.parse(out)), out);
    });
  });

  group('legacy canonicalization', () {
    test('a hand-authored legacy atom converges after one pass', () {
      // Legacy: id/origin/desc on <atom>, v/updated on the realms (today's tree).
      // First serialize is the desirable canonicalizing diff; second is stable.
      const legacy = '<atom id="x.soul" v="1.0" origin="Cafe" desc="a thing">'
          '<living-abstract v="1.0"><essence>e</essence></living-abstract>'
          '<living-concrete updated="2026-01-01"><knowledge name="k">x</knowledge></living-concrete>'
          '</atom>';
      final first = serializeAtom(XmlDocument.parse(legacy));
      final second = serializeAtom(XmlDocument.parse(first));
      expect(second, first, reason: 'canonical form must be stable after the first touch');
    });
  });
}
