import '../place.dart';

/// Renders the single-place card for `place info`: the name (with its
/// description), then the owner. Missing optional fields simply drop their line
/// — never a crash.
final class InfoRender {
  const InfoRender();

  String render(Place place) {
    final buf = StringBuffer();
    final desc = place.description;
    buf.writeln(desc == null ? place.name : '${place.name}  — $desc');
    final owner = place.owner;
    if (owner != null) buf.writeln('owner:  $owner');
    return buf.toString().trimRight();
  }
}
