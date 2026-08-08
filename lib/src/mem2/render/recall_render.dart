import '../model/mem_page.dart';
import '../relative_age.dart';
import '../word_count.dart';

/// Renders recalled pages, each under a separator rule + title line
/// (`topic · mode · attention · words · modified-age`), then the full body. The
/// rule makes a multi-page recall unambiguous at the seams; the modified-age
/// rides in the header so the mind holds each page's freshness while reading it,
/// and the weight beside it so a page that has swollen shows it at the moment of
/// re-speaking. The unit is written out — a bare magnitude is not a measurement.
final class RecallRender {
  const RecallRender(this.age, {this.wordCount = const WordCount()});

  final RelativeAge age;
  final WordCount wordCount;

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
      '${wordCount.count(page.body)} words',
      if (f.modified != null) 'modified ${age.of(f.modified!)} ago',
      if (f.assumptions.isNotEmpty)
        '⚠assumed:${f.assumptions.map((a) => a.field).join(',')}',
    ];
    return parts.join('  ·  ');
  }
}
