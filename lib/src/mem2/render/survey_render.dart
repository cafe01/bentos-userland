import '../../place/model/place.dart';
import '../model/mem_page.dart';
import '../relative_age.dart';
import '../word_count.dart';

/// Renders the memory map — pages grouped by mode (the label once per group),
/// one flowing line each: `attention  topic — gist`, then the trailing signal
/// cluster `#tags  ·age  [Nw]  @place`. `[Nw]` shows only above the size
/// threshold; `@place` only when the page is inherited from an ancestor. The
/// affordance footer trails the map. Logic-light; no template store.
final class SurveyRender {
  const SurveyRender({required this.age, this.wordCount = const WordCount()});

  final RelativeAge age;
  final WordCount wordCount;

  static const footer = 'read full → mem recall <topic>';

  /// The guidance shown when the map is empty — the caller routes it to stderr
  /// and exits 1.
  static const emptyGuidance =
      'mem: no pages yet — begin one with `mem remember <topic>`.';

  /// Render [pages] (already selected, in composition order) as the map. The
  /// [vantage] distinguishes an inherited page (its origin differs) so `@place`
  /// only marks what is not local.
  String render(List<MemPage> pages, {required Place vantage}) {
    final buf = StringBuffer();
    MemType? lastMode;
    for (final page in pages) {
      final mode = page.fields.type;
      if (mode != lastMode) {
        buf.writeln(mode.name);
        lastMode = mode;
      }
      buf.writeln('  ${_line(page, vantage)}');
    }
    buf
      ..writeln()
      ..write(footer);
    return buf.toString();
  }

  String _line(MemPage page, Place vantage) {
    final f = page.fields;
    final core = StringBuffer('${f.attention.render()}  ${page.topic}');
    if (f.gist != null) core.write(' — ${f.gist}');

    final cluster = <String>[];
    if (f.tags.isNotEmpty) cluster.add(f.tags.map((t) => '#$t').join(' '));
    if (f.modified != null) cluster.add('·${age.of(f.modified!)}');
    final size = wordCount.hint(page.body);
    if (size != null) cluster.add(size);
    final origin = page.origin;
    if (origin != null && origin.root.path != vantage.root.path) {
      cluster.add('@${origin.name}');
    }

    return cluster.isEmpty ? core.toString() : '$core  ${cluster.join('  ')}';
  }
}
