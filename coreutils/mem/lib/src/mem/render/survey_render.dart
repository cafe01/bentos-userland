import '../model/mem_node.dart';
import '../word_count.dart';

/// Renders the survey menu — grouped by mode, one line per page.
final class SurveyRender {
  const SurveyRender({WordCount? wordCount})
      : wordCount = wordCount ?? const WordCount();

  final WordCount wordCount;

  /// Render [pages] as the survey menu.
  ///
  /// Groups by mode (label once), line shape: `weight  name — gist [Nw?]`.
  /// Appends the affordance footer. Returns stderr guidance on empty input.
  ///
  /// [bodies] maps page name → raw content (frontmatter + body). When present,
  /// gist is extracted from frontmatter and word count drives the size hint.
  String render(List<MemPage> pages, {Map<String, String> bodies = const {}}) {
    throw UnimplementedError('SurveyRender.render not yet implemented');
  }
}
