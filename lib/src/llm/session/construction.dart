/// The delivery, as one object: every collaborator reachable on its own.
///
/// This is the whole seam between the two chairs. The contract suite arrives
/// through here and knows no concrete class, so each layer is judged where it
/// lives — the pure pieces with no double at all, the readers over a fake
/// primitive, the face over doubled readers.
library;

import 'attribution.dart';
import 'coordinate.dart';
import 'face.dart';
import 'machine.dart';
import 'primitive.dart';
import 'readers.dart';
import 'session.dart';
import 'session_view.dart';
import 'transcript.dart';
import 'turn.dart';

final class LlmSessionConstruction implements SessionConstruction {
  const LlmSessionConstruction();

  @override
  Attribution get attribution => const SpeakerRule();

  @override
  TranscriptView get view => const LensedView();

  @override
  MachineReader machineOver(Primitive primitive) =>
      MachineOverPrimitive(primitive);

  @override
  TranscriptReader transcriptsOver(Primitive primitive) =>
      TranscriptOverPrimitive(primitive);

  @override
  CoordinateSource coordinatesOver(Primitive primitive) =>
      CoordinateOverPrimitive(primitive);

  @override
  Rest restOver(MachineReader machine) => PollingRest(machine);

  @override
  SessionFace face({
    required Primitive primitive,
    required CoordinateSource coordinates,
    required MachineReader machine,
    required TranscriptReader transcripts,
    required TranscriptView view,
    required Rest rest,
  }) =>
      Session(
        primitive: primitive,
        coordinates: coordinates,
        machine: machine,
        transcripts: transcripts,
        view: view,
        rest: rest,
      );
}

/// What the plug point reaches.
const SessionConstruction sessionConstruction = LlmSessionConstruction();
