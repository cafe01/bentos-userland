import '../model/mem_frontmatter.dart';
import '../model/mem_node.dart';
import '../word_count.dart';

/// Renders the survey menu — grouped by mode, one line per page.
final class SurveyRender {
  const SurveyRender({WordCount? wordCount})
      : wordCount = wordCount ?? const WordCount();

  final WordCount wordCount;

  static const kFooter =
      'pull any one in full: mem recall <name>. feel the whole shape, cold included: mem survey.';

  /// Render [pages] as the survey menu, including the affordance footer.
  ///
  /// Use [renderBody] when the footer must be routed separately (e.g. to err).
  String render(List<MemPage> pages, {Map<String, String> bodies = const {}}) {
    final body = renderBody(pages, bodies: bodies);
    if (pages.isEmpty) return body;
    return '$body\n$kFooter';
  }

  /// Render [pages] as the survey menu body — grouped by mode, no footer.
  ///
  /// [bodies] maps page name → raw content (frontmatter + body). When present,
  /// gist is extracted from frontmatter and word count drives the size hint.
  String renderBody(List<MemPage> pages, {Map<String, String> bodies = const {}}) {
    if (pages.isEmpty) {
      return 'No pages yet. Use `mem remember <name>` to create your first page.\n';
    }

    final grouped = <MemPageType, List<MemPage>>{};
    for (final page in pages) {
      grouped.putIfAbsent(page.type, () => []).add(page);
    }

    final buf = StringBuffer();
    for (final type in kCompositionOrder) {
      final group = grouped[type];
      if (group == null) continue;
      buf.writeln(type.name);
      for (final page in group) {
        final body = bodies[page.name];
        String? gist;
        String? sizeHint;
        if (body != null) {
          final (fm, _) = FrontmatterFields.parse(body);
          gist = fm.gist;
          sizeHint = wordCount.hint(body);
        }
        final namePart = page.name;
        final weightPart = page.weight.toStringAsFixed(1);
        final gistPart = gist != null ? ' — $gist' : '';
        final sizePart = sizeHint != null ? '  $sizeHint' : '';
        buf.writeln('  w:$weightPart  $namePart$gistPart$sizePart');
      }
    }
    return buf.toString();
  }
}
