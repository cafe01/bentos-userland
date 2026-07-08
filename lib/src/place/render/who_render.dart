import '../place.dart';

/// Renders presence for `place who`: the tenants anchored directly at a
/// place, and — with `--all` — the ancestor-inherited ones, each tagged
/// `@place`. An uninhabited place renders honestly (`(nobody)`), never an error.
final class WhoRender {
  const WhoRender();

  String render(Place place, {bool all = false}) {
    final buf = StringBuffer();
    final here = place.plots;
    buf.writeln('here:   ${here.isEmpty ? '(nobody)' : here.join(', ')}');

    if (!all) return buf.toString().trimRight();

    final inherited = <String>[];
    for (final ancestor in place.ancestors) {
      for (final who in ancestor.plots) {
        inherited.add('$who@${ancestor.name}');
      }
    }
    if (inherited.isNotEmpty) buf.writeln('above:  ${inherited.join(', ')}');
    return buf.toString().trimRight();
  }
}
