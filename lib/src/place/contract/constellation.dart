/// `constellation` — standing and movement at the place's scale: per instance
/// per source, under a scope always stated, the pin folded in as *held*,
/// movement per pair with one failure stopping nothing (R12.1, R12.2, §7).
library;

import '../../entity/contract/contract.dart';
import 'place.dart';
import 'record.dart';

Never _todo(String member) => throw UnimplementedError('Constellation.$member');

/// R30 — the scope is always stated and never assumed.
sealed class Scope {
  const Scope();
}
final class OneInstance extends Scope {
  const OneInstance(this.thing, this.instance);
  final String thing;
  final String instance;
}
final class OneThing extends Scope {
  const OneThing(this.thing);
  final String thing;
}
final class ThisPlace extends Scope {
  const ThisPlace();
}
final class PlaceAndRooms extends Scope {
  const PlaceAndRooms();
}

final class Constellation {
  Constellation(this.place);
  final Place place;

  /// R29 — one line per instance per source, offline, each carrying the
  /// entity's relation, its age, and both counts; a pinned instance reads
  /// `held` with the distance the source has moved past the pin (R12.1).
  /// The place's own arrangement is one more thing in the list (R34).
  List<StandingLine> standing(Scope scope) => _todo('standing');

  /// R31, R12.2 — per instance–source pair; each pair alone; a held
  /// instance is reported held and not moved.
  Future<Report> move(Direction direction, Scope scope) => _todo('move');
}

/// The arrangement's own name in a `StandingLine`, since it is not a thing.
const String arrangementThing = '.place';

final class StandingLine {
  const StandingLine({required this.thing, required this.instance, required this.source, required this.standing, this.held, this.room});
  final String thing;
  final String instance;
  final Source source;
  final Standing standing;
  final Held? held;
  /// The room this line was read in, under `PlaceAndRooms`; null at the top.
  final String? room;
}
final class Held {
  const Held({required this.pin, required this.pastPin});
  final Pin pin;
  final int pastPin;
}

final class Report {
  const Report({required this.direction, required this.scope, required this.pairs});
  final Direction direction;
  final Scope scope;
  final List<PairOutcome> pairs;
}
final class PairOutcome {
  const PairOutcome({required this.thing, required this.instance, required this.source, required this.movement, this.room});
  final String thing;
  final String instance;
  final Source source;
  final Movement movement;
  final String? room;
}
sealed class Movement {
  const Movement();
}
/// The entity's own report crosses unflattened.
final class Answered extends Movement {
  const Answered(this.report);
  final MoveReport report;
}
/// R12.2 — held here; not moved; change or release the pin to move it.
final class HeldPair extends Movement {
  const HeldPair(this.pin);
  final Pin pin;
}
/// The thing is recorded and not stood here; nothing to ask.
final class NotStood extends Movement {
  const NotStood();
}
