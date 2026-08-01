/// A remote participant of an entity — a name and the address bytes move
/// through.
///
/// A remote is **not** an authority. Which copy of an entity is authoritative
/// is declared, never computed, and `origin` is a default rather than a truth;
/// the platform holds many copies of one identity at many coordinates and
/// declines to elect one. What a remote gives is reach: somewhere to push to,
/// somewhere to fetch from.
final class Remote {
  const Remote({required this.name, required this.url});

  final String name;
  final String url;

  @override
  String toString() => '$name\t$url';
}
