import '../place/model/place.dart';
import 'model/attention.dart';
import 'model/mem_page.dart';

/// One page's attention move — the before/after a bulk `refocus` echoes, with
/// the clamp flag set when a relative shift hit a rail.
final class RefocusChange {
  const RefocusChange(this.page, this.from, this.to, {this.clamped = false});

  final MemPage page;
  final Attention from;
  final Attention to;
  final bool clamped;
}

/// The intrinsic verify-back: after any mutation, render the landed post-state
/// so the mind never has to `recall` to confirm its own write. `@place` is
/// written whenever the page did not land at the vantage; a bulk refocus lists
/// each page's `old → new` with clamps marked. The echo reflects disk, not
/// intent.
final class WriteEcho {
  const WriteEcho(this.vantage);

  /// The vantage place — an origin differing from it is what draws `@place`.
  final Place vantage;

  /// `remember` landed [page]. [created] distinguishes a first write from a
  /// replace so the date note reads honestly.
  String remembered(MemPage page, {required bool created}) {
    final f = page.fields;
    final parts = <String>['remembered  ${page.topic}  (${f.type.name} · a:${f.attention.render()})'];
    if (f.tags.isNotEmpty) parts.add(f.tags.map((t) => '#$t').join(' '));
    final at = _place(page);
    if (at != null) parts.add(at);
    parts.add(created ? '· created now' : '· modified now');
    return parts.join('  ');
  }

  /// `forget` deleted [pages]. Each line names the released page and its last
  /// attention — content deleted, not merely cooled.
  String forgot(List<MemPage> pages) => pages
      .map((p) => 'forgot  ${p.topic}  (${p.fields.type.name} · was a:${p.fields.attention.render()})  — content deleted')
      .join('\n');

  /// `refocus` moved [changes]. A single change echoes on one line; a bulk move
  /// leads with a count and [selector], then lists every `old → new` with
  /// clamps marked.
  String refocused(List<RefocusChange> changes, {String? selector, String? by}) {
    if (changes.length == 1) {
      final c = changes.single;
      final clamp = c.clamped ? '  (clamped)' : '';
      final at = _place(c.page);
      final where = at != null ? '  $at' : '';
      return 'refocused  ${c.page.topic}  ${c.from.render()} → ${c.to.render()}$clamp$where';
    }
    final head = StringBuffer('refocused ${changes.length} pages');
    if (selector != null) head.write('  ($selector)');
    if (by != null) head.write('  --by $by');
    final buf = StringBuffer(head);
    for (final c in changes) {
      buf.write('\n  ${c.from.render()} → ${c.to.render()}  ${c.page.topic}');
      if (c.clamped) buf.write('   (clamped)');
    }
    return buf.toString();
  }

  String? _place(MemPage page) {
    final origin = page.origin;
    if (origin == null || origin.root.path == vantage.root.path) return null;
    return '@${origin.name}';
  }
}
