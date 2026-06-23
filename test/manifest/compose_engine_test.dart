import 'package:file/memory.dart';
import 'package:xml/xml.dart';
import 'package:bentos_userland/src/manifest/compose_engine.dart';
import 'package:bentos_userland/src/manifest/path_resolver.dart';
import 'package:test/test.dart';

/// The XInclude namespace, declared on every fixture root that uses `<xi:include>`.
const _xi = 'xmlns:xi="http://www.w3.org/2001/XInclude"';

void _seed(MemoryFileSystem fs, String path, String content) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

/// Names of the direct child elements of [doc]'s root, in document order.
List<String> _childNames(XmlDocument doc) =>
    doc.rootElement.childElements.map((e) => e.name.local).toList();

void main() {
  late MemoryFileSystem fs;
  late ComposeEngine engine;

  setUp(() {
    fs = MemoryFileSystem();
    engine = ComposeEngine(PathResolver(fs, const ['/tree']));
  });

  group('compose — no includes', () {
    test('passes the source through unchanged', () {
      final doc = engine.compose('<atom id="x"><body>hi</body></atom>', '/tree');
      expect(doc.findAllElements('body').single.innerText, 'hi');
      expect(doc.findAllElements('include'), isEmpty);
    });
  });

  group('compose — single include, splice atom-wrapper', () {
    test('relative include resolves against baseDir and replaces the node', () {
      _seed(fs, '/tree/pkg/part.xml', '<part>PART</part>');
      final doc = engine.compose(
        '<root $_xi><xi:include href="part.xml"/></root>',
        '/tree/pkg',
      );
      // The resolved root element replaces the xi:include verbatim, no stripping.
      expect(doc.findAllElements('part').single.innerText, 'PART');
      // No xi:include survives a successful composition.
      expect(doc.findAllElements('include'), isEmpty);
    });

    test('FQDN include resolves against the tree root, baseDir irrelevant', () {
      _seed(
        fs,
        '/tree/faculty/anamnesis/anamnesis.xml',
        '<atom id="anamnesis.faculty">A</atom>',
      );
      final doc = engine.compose(
        '<organism><xi:include href="anamnesis.faculty" $_xi/></organism>',
        '/some/unrelated/dir',
      );
      expect(doc.findAllElements('atom').single.innerText, 'A');
    });
  });

  group('compose — recursion & baseDir propagation', () {
    test("a nested include resolves against the INCLUDED file's own dir", () {
      // aa.xml lives in /tree/faculty/aa and pulls a sibling b.xml by RELATIVE
      // href — which must resolve in aa's dir, NOT the root entrypoint's baseDir.
      _seed(
        fs,
        '/tree/faculty/aa/aa.xml',
        '<atom $_xi><xi:include href="b.xml"/></atom>',
      );
      _seed(fs, '/tree/faculty/aa/b.xml', '<b>DEEP</b>');
      final doc = engine.compose(
        '<root $_xi><xi:include href="aa.faculty"/></root>',
        '/x',
      );
      // DEEP only appears if recursion happened AND b.xml resolved beside aa.xml.
      expect(doc.findAllElements('b').single.innerText, 'DEEP');
      expect(doc.findAllElements('include'), isEmpty);
    });
  });

  group('compose — v1 is PURE PREPROCESSOR (no dedup; that is the v2 linker)', () {
    test('a diamond pastes the shared particle TWICE, not once', () {
      _seed(fs, '/tree/faculty/leaf/leaf.xml', '<leaf>L</leaf>');
      final doc = engine.compose(
        '<root $_xi>'
        '<xi:include href="leaf.faculty"/>'
        '<xi:include href="leaf.faculty"/>'
        '</root>',
        '/x',
      );
      // Preprocessor duplicates by design; <binds> dedup is OUT OF SCOPE in v1.
      expect(doc.findAllElements('leaf').length, 2);
    });
  });

  group('compose — document order preserved', () {
    test('a spliced include keeps its position among literal siblings', () {
      _seed(fs, '/tree/faculty/leaf/leaf.xml', '<leaf>L</leaf>');
      final doc = engine.compose(
        '<root $_xi><before/><xi:include href="leaf.faculty"/><after/></root>',
        '/x',
      );
      expect(_childNames(doc), ['before', 'leaf', 'after']);
    });
  });

  group('compose — guards abort with ComposeException', () {
    test('a missing include throws', () {
      expect(
        () => engine.compose(
          '<root $_xi><xi:include href="ghost.faculty"/></root>',
          '/x',
        ),
        throwsA(isA<ComposeException>()),
      );
    });

    test('an include cycle throws (x → y → x)', () {
      _seed(
        fs,
        '/tree/faculty/x/x.xml',
        '<atom $_xi><xi:include href="y.faculty"/></atom>',
      );
      _seed(
        fs,
        '/tree/faculty/y/y.xml',
        '<atom $_xi><xi:include href="x.faculty"/></atom>',
      );
      expect(
        () => engine.compose(
          '<root $_xi><xi:include href="x.faculty"/></root>',
          '/x',
        ),
        throwsA(isA<ComposeException>()),
      );
    });
  });
}
