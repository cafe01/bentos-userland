/// `arrangement` — the record as a value and the acts that change it. The one
/// component that stands and holds the place's own copy, and the only one that
/// lands anything on it (§2, §3, R14, R27, R33, R34).
library;

import 'dart:io';

import '../../entity/contract/contract.dart';
import 'record.dart';

Never _todo(String member) => throw UnimplementedError('Arrangement.$member');

/// The record of one place at one line — in view, or as of an instant.
/// A value: read whole, never mutated in place. Holds only what nobody else
/// holds; everything a copy can answer is asked of the copy (R10, R13).
final class Arrangement {
  Line get line => _todo('line');

  /// Non-null when read as of an instant (R27).
  DateTime? get asOf => _todo('asOf');
  Card get card => _todo('card');
  Lineage? get above => _todo('above');

  List<ThingEntry> get things => _todo('things');
  List<RoomEntry> get rooms => _todo('rooms');
  List<Resident> get residents => _todo('residents');
  List<Pin> get pins => _todo('pins');

  ThingEntry? thing(String name) => _todo('thing');
  RoomEntry? room(String name) => _todo('room');
  Pin? pin(String thing, String instance) => _todo('pin');

  /// R14, R16 — the anchor: `<root>/<name>`. The instance's address beneath
  /// it is `Presence`'s rule.
  Directory anchorOf(String thing) => _todo('anchorOf');
  Directory roomOf(String name) => _todo('roomOf');

  /// The copy standing at a recorded thing's anchor; null when recorded and
  /// not yet stood here. The one member through which `Presence`, `Survey`
  /// and `Constellation` reach a thing.
  Copy? copyOf(String thing) => _todo('copyOf');

  // ── acts: one signed landing each, on the line's instance ──────────

  /// R11, R21 — install: read the declaration at [address], refuse a name
  /// already recorded here, stand the copy light at its anchor with its slice
  /// of the plot, land the entry with [address] as the stand-from address.
  Future<Outcome<ThingEntry>> install(String address, {required Actor actor}) => _todo('install');

  /// R28 — remove the entry. The copy stays; nothing is destroyed.
  Future<Outcome<void>> remove(String thing, {required Actor actor}) => _todo('remove');

  /// R5 — the stand-from address changes only by saying so.
  Future<Outcome<void>> restandFrom(String thing, String address, {required Actor actor}) => _todo('restandFrom');

  /// R6 — rooms.
  Future<Outcome<RoomEntry>> addRoom(String name, {String? standFrom, required Actor actor}) => _todo('addRoom');
  Future<Outcome<void>> removeRoom(String name, {required Actor actor}) => _todo('removeRoom');

  /// R8 — residence.
  Future<Outcome<Resident>> reside(String name, {required String kind, required Actor actor}) => _todo('reside');
  Future<Outcome<void>> leave(String name, {required Actor actor}) => _todo('leave');

  /// R12 — hold an instance at a point, or stop holding it.
  Future<Outcome<Pin>> hold(String thing, String instance, Point at, {required Actor actor}) => _todo('hold');
  Future<Outcome<void>> unhold(String thing, String instance, {required Actor actor}) => _todo('unhold');

  // ── R33: stand what the record names ───────────────────────────────

  /// For every recorded thing not yet stood: `Copy.stand` light at its
  /// anchor. For every recorded room with an address not yet standing:
  /// `Place.carry` at `roomOf`. Per entry, one failure stops nothing.
  Future<List<Stood>> materialize() => _todo('materialize');

  // ── R34: the place's own standing and movement ─────────────────────

  List<Source> get sources => _todo('sources');
  List<SourceStanding> get standing => _todo('standing');
  Future<List<MoveReport>> move(Direction direction) => _todo('move');
}

/// The place's own line against one of its sources (R34).
final class SourceStanding {
  const SourceStanding({required this.line, required this.source, required this.standing});
  final Line line;
  final Source source;
  final Standing standing;
}

/// A write's outcome: the floor's four, unflattened, plus this component's own
/// refusals, each a distinct obligation on the caller.
sealed class Outcome<T> {
  const Outcome();
}
final class Landed<T> extends Outcome<T> {
  const Landed(this.value);
  final T value;
}
/// The arrangement moved under the act; re-read and retried, bounded; this is
/// what remains after the third refusal.
final class Contested<T> extends Outcome<T> {
  const Contested();
}
final class Diverged<T> extends Outcome<T> {
  const Diverged();
}
final class Gated<T> extends Outcome<T> {
  const Gated(this.words);
  final String words;
}
/// R21 — a thing of this name already stands here.
final class Duplicate<T> extends Outcome<T> {
  const Duplicate(this.name);
  final String name;
}
/// Entity R2.5.3 — the declaration at the address could not be read.
final class Undeclared<T> extends Outcome<T> {
  const Undeclared(this.address, this.reason);
  final String address;
  final String reason;
}
/// The address could not be reached; nothing was recorded.
final class Unreachable<T> extends Outcome<T> {
  const Unreachable(this.address);
  final String address;
}
/// A writing member on an implicit place.
final class NotAPlace<T> extends Outcome<T> {
  const NotAPlace();
}

/// One entry of `materialize`'s report.
final class Stood {
  const Stood({required this.name, required this.stood, this.reason});
  final String name;
  final bool stood;
  final String? reason;
}

/// The record file is of a schema this build does not read. Refused legibly,
/// never misread.
final class UnreadableRecord implements Exception {
  const UnreadableRecord(this.path, this.reason);
  final String path;
  final String reason;
}
