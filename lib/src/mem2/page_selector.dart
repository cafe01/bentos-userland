import 'model/attention.dart';
import 'model/mem_page.dart';

/// The predicate engine — the shared *reach* axis for survey, recall, and
/// refocus. Filters a page set by attention bounds (inclusive, exact over
/// integer tenths), mode, and tag; all predicates compose as AND. Returns the
/// matches in composition order (autobiographical → episodic → semantic →
/// procedural → prospective), preserving input order within each mode. Pure.
final class PageSelector {
  const PageSelector();

  List<MemPage> select(
    List<MemPage> pages, {
    Attention? minAttention,
    Attention? maxAttention,
    MemType? type,
    String? tag,
  }) {
    final result = <MemPage>[];
    for (final mode in MemType.values) {
      if (type != null && mode != type) continue;
      for (final page in pages) {
        if (page.fields.type != mode) continue;
        final a = page.fields.attention.tenths;
        if (minAttention != null && a < minAttention.tenths) continue;
        if (maxAttention != null && a > maxAttention.tenths) continue;
        if (tag != null && !page.fields.tags.contains(tag)) continue;
        result.add(page);
      }
    }
    return result;
  }
}
