import 'model/mem_frontmatter.dart';
import 'model/mem_node.dart';

/// Predicate-based page selection — the shared reach axis for survey and recall.
///
/// Filters the pages of a [MemNode] by the given predicates and returns
/// them in composition order (autobiographical → episodic → semantic →
/// procedural → prospective). All predicates compose as AND.
final class PageSelector {
  const PageSelector();

  List<MemPage> select(
    MemNode node, {
    double? minWeight,
    double? maxWeight,
    MemPageType? type,
    String? tag,
  }) {
    final result = <MemPage>[];
    for (final orderedType in kCompositionOrder) {
      if (type != null && orderedType != type) continue;
      for (final page in node.pagesOf(orderedType)) {
        if (minWeight != null && page.weight < minWeight) continue;
        if (maxWeight != null && page.weight > maxWeight) continue;
        if (tag != null && !_hasTag(node, page, tag)) continue;
        result.add(page);
      }
    }
    return result;
  }

  bool _hasTag(MemNode node, MemPage page, String tag) {
    final content = node.readContent(page);
    if (content == null) return false;
    final (fields, _) = FrontmatterFields.parse(content);
    return fields.tags?.contains(tag) ?? false;
  }
}
