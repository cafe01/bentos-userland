/// The record's values — the place's own, read from the arrangement's two
/// files and from nowhere inside a thing.
library;

import '../../entity/contract/contract.dart';

/// R2. Owner is a stated string, never derived from the machine.
final class Card {
  const Card({required this.name, this.description, this.owner});
  final String name;
  final String? description;
  final String? owner;
}

/// One line of the place: an instance of the arrangement entity, named.
final class Line {
  const Line(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is Line && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => 'Line($name)';
}

/// A thing recorded here, with the address to stand it from (R5).
final class ThingEntry {
  const ThingEntry({required this.name, required this.standFrom});
  final String name;
  final String standFrom;
}

/// A nested place recorded here, with the address to stand it from when it
/// has one (R6).
final class RoomEntry {
  const RoomEntry({required this.name, this.standFrom});
  final String name;
  final String? standFrom;
}

/// An inhabitant: a name and a declared kind, never interpreted (R8).
final class Resident {
  const Resident({required this.name, required this.kind});
  final String name;
  final String kind;
}

/// An instance held at a point (R12). A record of this place; the copy knows
/// nothing of it.
final class Pin {
  const Pin({required this.thing, required this.instance, required this.at});
  final String thing;
  final String instance;
  final Point at;
}

/// Where the place came from: the parent's name and, when it had one, the
/// address it stands from. What R22 names when a name would resolve through
/// an ancestor absent here.
final class Lineage {
  const Lineage({required this.name, this.standFrom});
  final String name;
  final String? standFrom;
}
