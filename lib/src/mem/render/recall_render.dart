import '../model/mem_frontmatter.dart';
import '../model/mem_node.dart';

/// Renders recalled pages — separator rule + title + telos + full body per page.
final class RecallRender {
  const RecallRender();

  static const _rule = '────────────────────────────────────────';

  /// Render [pages] each under their separator rule.
  ///
  /// [bodies] maps page name → raw content (frontmatter + body). Frontmatter is
  /// stripped; telos is shown highlighted; body follows.
  /// Missing body: renders title only, does not crash.
  String render(List<MemPage> pages, {Map<String, String> bodies = const {}}) {
    final buf = StringBuffer();
    for (final page in pages) {
      buf.writeln(_rule);
      buf.writeln('${page.name} (${page.type.name} w:${page.weight.toStringAsFixed(1)})');
      final body = bodies[page.name];
      if (body != null) {
        final (fm, bodyText) = FrontmatterFields.parse(body);
        if (fm.telos != null) buf.writeln(fm.telos);
        if (bodyText.isNotEmpty) buf.writeln(bodyText);
      }
    }
    return buf.toString();
  }
}
