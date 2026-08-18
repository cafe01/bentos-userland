/// `survey` — what stands here, read: things by declaration, instances by the
/// name the thing declares, rooms, residents, loose objects; present or not;
/// never cached (R6, R7, R9, R13; Places §8.1).
library;

import 'dart:io';

import '../../entity/contract/contract.dart';
import 'place.dart';
import 'record.dart';

Never _todo(String member) => throw UnimplementedError('Survey.$member');

final class Survey {
  Survey(this.place);
  final Place place;

  List<ThingView> get things => _todo('things');
  List<RoomView> get rooms => _todo('rooms');
  List<Resident> get residents => _todo('residents');

  /// R7 — top-level entries of the arrangement's tree that are neither
  /// `.place`, a recorded anchor, nor a recorded room. Names only.
  List<FileSystemEntity> get loose => _todo('loose');

  /// The whole desk in one value; what the face and the desk draw.
  Desk get desk => _todo('desk');
}

final class ThingView {
  const ThingView({required this.entry, this.manifest, this.undeclared, this.instances = const []});
  final ThingEntry entry;
  /// Null when not stood here.
  final Manifest? manifest;
  /// Non-null when the declaration could not be read: shown as an unknown
  /// thing, never hidden (Places R5).
  final String? undeclared;
  final List<InstanceView> instances;
}

final class InstanceView {
  const InstanceView({required this.instance, required this.present, this.held});
  final Instance instance;
  final bool present;
  final Pin? held;
}

sealed class RoomView {
  const RoomView();
}
final class StandingRoom extends RoomView {
  const StandingRoom(this.entry, this.place);
  final RoomEntry entry;
  final Place place;
}
final class RecordedRoom extends RoomView {
  const RecordedRoom(this.entry);
  final RoomEntry entry;
}
final class UnrecordedRoom extends RoomView {
  const UnrecordedRoom(this.at);
  final Directory at;
}

final class Desk {
  const Desk({required this.card, required this.line, required this.things, required this.rooms, required this.residents, required this.loose});
  final Card card;
  final Line line;
  final List<ThingView> things;
  final List<RoomView> rooms;
  final List<Resident> residents;
  final List<FileSystemEntity> loose;
}
