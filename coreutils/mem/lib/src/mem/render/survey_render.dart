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
  String render(List<MemPage> pages) {
    throw UnimplementedError('SurveyRender.render not yet implemented');
  }
}
