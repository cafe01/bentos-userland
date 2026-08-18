// Shared moves of the design suite. Every helper goes through the place's
// own surface; nothing here composes a `.place/…` path.
import 'dart:io';

import 'package:bentos_userland/src/entity/contract/contract.dart' hide Landed, Gated;
import 'package:bentos_userland/src/place/contract/contract.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_entity.dart';

/// Genesis of a marked place at [path], by [tester].
Future<Place> genesis(String path, {String? name, String? owner, Source? source}) =>
    Place(path).create(actor: tester, name: name ?? p.basename(path), owner: owner, source: source);

/// Seed a far thing at [address] and install it into [place].
Future<ThingEntry> installThing(FakeGate gate, Place place, String name,
    {String? address, List<Seed> instances = const [], String kind = 'thing', bool ownDivergence = false}) async {
  final addr = address ?? 'hub:/things/$name';
  gate.remotes[addr] = FakeRemote(manifestOf(name, kind: kind, ownDivergence: ownDivergence), instances: instances);
  final outcome = await place.arrangement.install(addr, actor: tester);
  return (outcome as Landed<ThingEntry>).value;
}

/// The copy the gate stood for [name] in [place].
FakeCopy copyOf(FakeGate gate, Place place, String name) => gate.copyAt(place.arrangement.anchorOf(name).path)!;

/// The arrangement copy of [place].
FakeCopy ownCopy(FakeGate gate, Place place) => gate.copyAt(place.root.path)!;

/// Write [content] at [path] inside an act's private area.
void writeIn(Act act, String path, String content) {
  File(p.join(act.directory.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

/// Land a hand-written record on [place]'s line — what an arriving landing
/// from another copy would leave in the tree.
Future<void> landRecord(FakeGate gate, Place place, {String? card, String? arrangement, Actor by = other}) =>
    ownCopy(gate, place).instance(place.line.name).act((a) {
      if (card != null) writeIn(a, '.place/card.yaml', card);
      if (arrangement != null) writeIn(a, '.place/arrangement.yaml', arrangement);
    }, by: by);

/// Seed a room at [address] and carry it to [at].
Future<Place> carryRoom(FakeGate gate, String address, String at, {String name = 'room', String? arrangement}) async {
  gate.remotes[address] = FakeRemote(manifestOf(name, kind: 'place'), instances: const [Seed('main', title: 'main')]);
  final room = await Place.carry(address, at: Directory(at));
  await landRecord(gate, room, card: 'name: $name\n', arrangement: arrangement ?? record());
  return room;
}

/// An arrangement record, in the schema this build reads.
String record({List<(String, String)> things = const [], List<(String, String?)> rooms = const [], (String, String?)? above}) {
  final b = StringBuffer('schema: 1\n');
  if (above != null) b.writeln('above:\n  name: ${above.$1}\n${above.$2 == null ? '' : '  standFrom: ${above.$2}\n'}');
  b.writeln('things:${things.isEmpty ? ' []' : ''}');
  for (final t in things) b.writeln('  - name: ${t.$1}\n    standFrom: ${t.$2}');
  b.writeln('rooms:${rooms.isEmpty ? ' []' : ''}');
  for (final r in rooms) b.writeln('  - name: ${r.$1}${r.$2 == null ? '' : '\n    standFrom: ${r.$2}'}');
  b.writeln('residents: []\npins: []');
  return b.toString();
}

/// The one way this suite asserts a standing: relation, both counts, and the
/// age — every value but `unknown` carries when the contact it rests on
/// happened, and `unknown` carries none (entity R2.9.1a, R2.9.2).
void expectStanding(Standing standing, Relation relation, {int behind = 0, int ahead = 0, String? reason}) {
  expect(standing.relation, relation, reason: reason);
  expect(standing.behind, behind, reason: 'behind — $reason');
  expect(standing.ahead, ahead, reason: 'ahead — $reason');
  if (relation == Relation.unknown) {
    expect(standing.contacted, isNull, reason: 'unknown is the one value that carries no age');
  } else {
    expect(standing.contacted, isNotNull, reason: 'a standing without an age is not an answer');
  }
}

Directory dir(String path) => Directory(path);
