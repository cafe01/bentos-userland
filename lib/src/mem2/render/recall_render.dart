import '../model/mem_page.dart';
import '../relative_age.dart';

/// Renders recalled pages, each under a separator rule + title line
/// (`topic · mode · attention · modified-age`), then the full body. The rule
/// makes a multi-page recall unambiguous at the seams; the modified-age rides
/// in the header so the mind holds each page's freshness while reading it.
final class RecallRender {
  const RecallRender(this.age);

  final RelativeAge age;

  static const _rule =
      '─────────────────────────────────────────────────────────';

  String render(List<MemPage> pages) {
    final buf = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      if (i > 0) buf.writeln();
      final page = pages[i];
      buf
        ..writeln(_rule)
        ..writeln(_title(page));
      if (page.body.isNotEmpty) {
        buf
          ..writeln()
          ..writeln(page.body);
      }
    }
    return buf.toString();
  }

  String _title(MemPage page) {
    final f = page.fields;
    final parts = <String>[
      page.topic,
      f.type.name,
      'a:${f.attention.render()}',
      if (f.modified != null) 'modified ${age.of(f.modified!)} ago',
    ];
    return parts.join('  ·  ');
  }
}
