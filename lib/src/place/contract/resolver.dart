/// `resolver` — a name to the nearest copy up the tree, a coordinate to its
/// path (R17, R20–R22). Where every walk the entity used to perform now lives.
library;

import 'dart:io';

import '../../entity/contract/contract.dart';
import 'place.dart';
import 'record.dart';

Never _todo(String member) => throw UnimplementedError('Resolver.$member');

final class Resolver {
  /// Resolve [name] from [vantage]: the enclosing place first, then each
  /// ancestor upward. Nearest wins. Reads records on the way and nothing
  /// inside any thing; offline; opens no copy until one is found.
  static Resolution resolve(String name, {required String vantage}) => _todo('resolve');

  /// R17 — the path of a coordinate by the uniform rule. Answers whether or
  /// not anything is present there. Null when the coordinate names a line
  /// that is not stood.
  static Directory? pathOf(Coordinate coordinate) => _todo('pathOf');
}

/// The place, the line, the thing, the instance identity. Line defaults to
/// the line in view; instance may be absent to mean the anchor.
final class Coordinate {
  const Coordinate({required this.place, this.line, required this.thing, this.instance});
  final Place place;
  final Line? line;
  final String thing;
  final String? instance;
}

sealed class Resolution {
  const Resolution();
}

/// Found: the copy standing at [anchor] in [place], recorded there. [copy] is
/// null when the thing is recorded and not yet stood.
final class Resolved extends Resolution {
  const Resolved({required this.place, required this.entry, required this.anchor, this.copy});
  final Place place;
  final ThingEntry entry;
  final Directory anchor;
  final Copy? copy;
}

/// R22 — nowhere on this machine, and the walk reached a place whose
/// lineage names an ancestor not present here. Named, never invented.
final class ThroughAbsentAncestor extends Resolution {
  const ThroughAbsentAncestor({required this.last, required this.ancestor, required this.searched});
  final Place last;
  final Lineage ancestor;
  final List<Place> searched;
}

/// In no place on the path, every ancestor present.
final class Unresolved extends Resolution {
  const Unresolved({required this.searched});
  final List<Place> searched;
}
