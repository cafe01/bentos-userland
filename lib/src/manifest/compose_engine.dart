import 'package:xml/xml.dart';

import 'path_resolver.dart';

const _xiNs = 'http://www.w3.org/2001/XInclude';

const _preservedElements = {
  'knowledge',
  'protocol',
  'pattern',
  'antipattern',
  'essence',
  'purpose',
  'capacity',
  'principle',
  'genesis',
};

/// Serialize a composed [XmlDocument] to a pretty-printed XML string.
///
/// - Preserves whitespace inside text-heavy elements (genesis, protocol, …).
/// - Strips orphaned `xmlns:xi` namespace declarations left after xi:include
///   resolution — all includes are already spliced out; the declaration is dead.
String serializeComposed(XmlDocument doc) {
  _stripXiNamespace(doc.rootElement);
  return doc.toXmlString(
    pretty: true,
    indent: '  ',
    preserveWhitespace: (node) =>
        node is XmlElement && _preservedElements.contains(node.name.local),
  );
}

void _stripXiNamespace(XmlElement el) {
  el.attributes.removeWhere(
    (attr) =>
        (attr.name.local == 'xi' && attr.name.prefix == 'xmlns') ||
        (attr.name.prefix == null &&
            attr.name.local == 'xmlns' &&
            attr.value == _xiNs),
  );
  for (final child in el.childElements) {
    _stripXiNamespace(child);
  }
}

/// Raised when a composition cannot complete: a missing include, an unresolvable
/// `href`, or an include cycle. The command layer catches it, writes [message] to
/// stderr, and exits 1.
final class ComposeException implements Exception {
  ComposeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The composition engine — the heart of `manifest build`/`check`.
///
/// SCOPE (v1 = PURE PREPROCESSOR). `manifest` composes a being by ONE mechanism:
/// recursive resolution of `<xi:include>`. This is the `#include` altitude —
/// textual, positional, dumb-by-design, and CORRECT for it. A module splits its
/// own body into parts (`atom.xml` includes `skill_abstract.xml` +
/// `skill_concrete.xml`) and the engine pastes each resolved root element in
/// place of its `<xi:include>` node.
///
/// EXPLICITLY OUT OF SCOPE (v2). Inter-atom dependency — `<binds to=…>`, the
/// LINKER altitude (depended-on emitted OUTSIDE the dependent, deduplicated like a
/// graph not a tree, ordered by first-mention). That is a SEPARATE pass with
/// separate semantics; the engine does not know `<binds>` exists. (The old `pkg`
/// collapsed linker into preprocessor — the root error this scoping avoids.)
///
/// THE ALGORITHM. compose(source, baseDir):
///  1. Parse `source` into an [XmlDocument].
///  2. Walk it; for each `<xi:include href=…>` in document order:
///     a. resolve href → (content, canonicalPath) via the [PathResolver];
///     b. cycle guard — if canonicalPath is already on the active stack, abort;
///     c. recurse into `content` FIRST, with baseDir = the included file's own
///        directory and the stack extended by canonicalPath, so its own relative
///        includes resolve correctly (baseDir PROPAGATION);
///     d. SPLICE atom-wrapper — the fully-expanded root element REPLACES the
///        `<xi:include>` node verbatim, no stripping:
///        `<organism><xi:include href="x.soul"/></organism>` becomes
///        `<organism><atom id="x.soul">…</atom></organism>`.
///  3. Return the flattened [XmlDocument]; the command serializes it (decision:
///     the engine stays in the tree domain, formatting is the command's call).
///
/// PURITY. The engine touches NO [FileSystem] — all IO flows through the injected
/// [PathResolver]. Inject a resolver over a `MemoryFileSystem` and the engine is
/// fully testable without a real file. Cycle stack and baseDir are private
/// recursion state; the public surface is the single [compose] call.
///
/// ENTRYPOINT. The root `source` is already-read text — an FQDN the command
/// resolved, or stdin. Its [baseDir] is the directory its OWN relative includes
/// resolve against (the resolved file's dir, or cwd for stdin).
final class ComposeEngine {
  ComposeEngine(this._resolver);

  final PathResolver _resolver;

  /// Compose [source] (root XML text) into a fully-flattened document, resolving
  /// every `<xi:include>` it transitively reaches against [baseDir]. Throws
  /// [ComposeException] on a missing include or a cycle.
  XmlDocument compose(String source, String baseDir) =>
      _compose(source, baseDir, const []);

  XmlDocument _compose(
    String source,
    String baseDir,
    List<String> cycleStack,
  ) {
    final doc = XmlDocument.parse(source);
    _expand(doc.rootElement, baseDir, cycleStack);
    return doc;
  }

  void _expand(XmlElement node, String baseDir, List<String> cycleStack) {
    for (final child in node.children.toList()) {
      if (child is XmlElement &&
          child.name.local == 'include' &&
          child.name.namespaceUri == 'http://www.w3.org/2001/XInclude') {
        final href = child.getAttribute('href');
        if (href == null) throw ComposeException('xi:include missing href');

        final resolved = _resolver.resolve(href, baseDir);
        if (resolved == null) {
          throw ComposeException('Include not found: $href');
        }

        if (cycleStack.contains(resolved.canonicalPath)) {
          throw ComposeException('Include cycle detected: ${resolved.canonicalPath}');
        }

        final includedDoc = _compose(
          resolved.content,
          _dirOf(resolved.canonicalPath),
          [...cycleStack, resolved.canonicalPath],
        );

        // Splice: replace <xi:include> with the fully-expanded root element.
        final spliced = includedDoc.rootElement.copy();
        child.replace(spliced);
      } else if (child is XmlElement) {
        _expand(child, baseDir, cycleStack);
      }
    }
  }

  String _dirOf(String path) {
    final idx = path.lastIndexOf('/');
    return idx <= 0 ? '/' : path.substring(0, idx);
  }
}
