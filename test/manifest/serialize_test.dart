import 'package:bentos_userland/src/manifest/compose_engine.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  group('serializeComposed — whitespace preservation', () {
    test('preserves newlines inside <genesis>', () {
      final doc = XmlDocument.parse(
        '<organism>'
        '<genesis>line one\nline two\nline three</genesis>'
        '</organism>',
      );
      final out = serializeComposed(doc);
      expect(out, contains('line one\nline two\nline three'));
    });

    test('preserves leading/trailing whitespace inside <protocol>', () {
      final doc = XmlDocument.parse(
        '<atom><protocol name="wake">\n  Step A.\n  Step B.\n</protocol></atom>',
      );
      final out = serializeComposed(doc);
      expect(out, contains('\n  Step A.\n  Step B.\n'));
    });

    test('preserves whitespace inside <knowledge>', () {
      final doc = XmlDocument.parse('<atom><knowledge>  text\n</knowledge></atom>');
      final out = serializeComposed(doc);
      expect(out, contains('  text\n'));
    });

    test('preserves whitespace inside <pattern>', () {
      final doc = XmlDocument.parse('<atom><pattern>a\nb</pattern></atom>');
      final out = serializeComposed(doc);
      expect(out, contains('a\nb'));
    });

    test('preserves whitespace inside <antipattern>', () {
      final doc = XmlDocument.parse('<atom><antipattern>a\nb</antipattern></atom>');
      final out = serializeComposed(doc);
      expect(out, contains('a\nb'));
    });

    test('preserves whitespace inside <principle>', () {
      final doc = XmlDocument.parse('<atom><principle>a\nb</principle></atom>');
      final out = serializeComposed(doc);
      expect(out, contains('a\nb'));
    });

    test('preserves whitespace inside <essence> and <purpose>', () {
      final doc = XmlDocument.parse(
        '<atom><essence>e\n</essence><purpose>p\n</purpose></atom>',
      );
      final out = serializeComposed(doc);
      expect(out, contains('e\n'));
      expect(out, contains('p\n'));
    });

    test('preserves whitespace inside <capacity>', () {
      final doc = XmlDocument.parse('<atom><capacity>c\n</capacity></atom>');
      final out = serializeComposed(doc);
      expect(out, contains('c\n'));
    });
  });

  group('serializeComposed — xmlns:xi stripped from output', () {
    test('strips xmlns:xi from the root element', () {
      final doc = XmlDocument.parse(
        '<organism xmlns:xi="http://www.w3.org/2001/XInclude">'
        '<atom id="foo"/>'
        '</organism>',
      );
      final out = serializeComposed(doc);
      expect(out, isNot(contains('xmlns:xi')));
    });

    test('strips xmlns:xi from nested elements', () {
      final doc = XmlDocument.parse(
        '<organism>'
        '<atom id="foo" xmlns:xi="http://www.w3.org/2001/XInclude"/>'
        '</organism>',
      );
      final out = serializeComposed(doc);
      expect(out, isNot(contains('xmlns:xi')));
    });

    test('strips the XInclude namespace URI variant too', () {
      final doc = XmlDocument.parse(
        '<organism xmlns="http://www.w3.org/2001/XInclude"><atom/></organism>',
      );
      final out = serializeComposed(doc);
      expect(out, isNot(contains('http://www.w3.org/2001/XInclude')));
    });

    test('does not strip other namespaces', () {
      final doc = XmlDocument.parse(
        '<organism xmlns:foo="http://example.com"><atom/></organism>',
      );
      final out = serializeComposed(doc);
      expect(out, contains('xmlns:foo'));
    });
  });

  group('serializeComposed — general formatting', () {
    test('output is valid XML', () {
      final doc = XmlDocument.parse(
        '<organism xmlns:xi="http://www.w3.org/2001/XInclude">'
        '<atom id="a"><genesis>hello\nworld</genesis></atom>'
        '</organism>',
      );
      final out = serializeComposed(doc);
      // Must round-trip as valid XML.
      expect(() => XmlDocument.parse(out), returnsNormally);
    });
  });
}
