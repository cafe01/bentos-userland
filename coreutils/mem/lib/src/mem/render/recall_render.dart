import '../model/mem_node.dart';

/// Renders recalled pages — separator rule + title + telos + full body per page.
final class RecallRender {
  const RecallRender();

  /// Render [pages] each under their separator rule.
  ///
  /// Single page: rule + title line (name · mode · w) + telos + body.
  /// N pages: N rules, no ambiguity at seams.
  /// Missing body: renders honestly, does not crash.
  String render(List<MemPage> pages) {
    throw UnimplementedError('RecallRender.render not yet implemented');
  }
}
