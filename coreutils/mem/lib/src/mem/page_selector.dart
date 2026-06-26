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
    throw UnimplementedError('PageSelector.select not yet implemented');
  }
}
