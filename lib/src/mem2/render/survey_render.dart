import '../../place/place.dart';
import '../model/mem_page.dart';
import '../relative_age.dart';
import '../word_count.dart';

/// Renders the memory map — pages grouped by mode (the label once per group),
/// one flowing line each: `attention  topic — gist`, then the trailing signal
/// cluster `#tags  ·age  [Nw]  @place`. `[Nw]` shows only above the size
/// threshold; `@place` only when the page is inherited from an ancestor. The
/// legend heads the map and the affordance footer trails it. Logic-light; no
/// template store.
final class SurveyRender {
  const SurveyRender({required this.age, this.wordCount = const WordCount()});

  final RelativeAge age;
  final WordCount wordCount;

  /// The column legend. `[words]` is spelled out on purpose: the compact `[Nw]`
  /// hint repeats down the map, so the unit is declared once at the point of
  /// reading rather than left to a convention the reader must already hold.
  static const legend =
      'attention  topic — gist   #tags  ·modified  [words]  @place';

  static const footer = 'read full → mem recall <topic>';

  /// The guidance shown when the bank itself holds nothing — the caller routes
  /// it to stderr.
  static const emptyGuidance =
      'mem: no pages yet — begin one with `mem remember <topic>`.';

  /// The note shown when a populated bank held nothing under the asked reach.
  /// The reach is echoed so the caller can see what it actually asked for.
  static String noMatch(String reach) => 'mem: no pages under $reach.';

  /// The line a bounded map carries under its legend: which slice of the whole
  /// this is, and — only when a tail actually remains — how to ask for the rest.
  /// A next-page affordance printed at the end of the map is the same lie as a
  /// silent truncation, inverted.
  static String truncation({
    required int from,
    required int to,
    required int total,
  }) {
    final line = 'showing $from–$to of $total, hottest first';
    return to < total ? '$line → mem survey --offset $to' : line;
  }

  /// Render [pages] (already selected and ordered) as the map. The [vantage]
  /// distinguishes an inherited page (its origin differs) so `@place` only marks
  /// what is not local. [notice] heads the map when the caller bounded it —
  /// before the groups, since a truncated mode group must not be read as
  /// complete on the way down.
  String render(
    List<MemPage> pages, {
    required Place vantage,
    String? notice,
  }) {
    final buf = StringBuffer()..writeln(legend);
    if (notice != null) buf.writeln(notice);
    buf.writeln();
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
    // A degraded page must never sit in the map looking exactly like an
    // authored one — the full disclosure is on stderr, this is the mark that
    // makes it visible where the map is actually read.
    if (f.assumptions.isNotEmpty) {
      cluster.add('⚠${f.assumptions.map((a) => a.field).join(',')}');
    }

    return cluster.isEmpty ? core.toString() : '$core  ${cluster.join('  ')}';
  }
}
