/// The readers: everything that turns the primitive's answers into the face's
/// vocabulary, and nothing else.
///
/// They stand over whatever [Primitive] they are handed, which is what lets the
/// gate judge them against a fake floor holding a real tree.
library;

import 'dart:convert';

import 'package:chat_inference/chat_inference.dart';

import 'coordinate.dart';
import 'face.dart';
import 'machine.dart';
import 'primitive.dart';
import 'transcript.dart';
import 'turn.dart';

/// Where a session's messages stand in the tree.
const String messagesPath = 'llm/messages';

/// Reading the transcript through the ontology — `ls` for the list, `read` for
/// the bytes, both at the same point in history.
final class TranscriptOverPrimitive implements TranscriptReader {
  const TranscriptOverPrimitive(this.primitive);

  final Primitive primitive;

  @override
  Future<List<String>> messageNames(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    final listed = await primitive.ls(
      coord,
      messagesPath,
      asOf: asOf,
      vantage: vantage,
    );
    final names = [
      for (final path in listed)
        if (!path.endsWith('.gitkeep')) path,
    ];
    // The names carry their own chronology, and the listing's order is the
    // floor's business. Sorting here is what keeps a transcript in order when
    // the floor hands one back reversed.
    names.sort();
    return names;
  }

  @override
  Future<List<StoredMessage>> transcript(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    final names = await messageNames(coord, asOf: asOf, vantage: vantage);
    return [
      for (final path in names)
        StoredMessage(
          path,
          await _decode(
            path,
            await primitive.read(coord, path, asOf: asOf, vantage: vantage),
          ),
        ),
    ];
  }

  /// A `.jsonl` is an assistant's event stream, folded by the library that owns
  /// folding; a `.json` is one message already. Nothing is folded here.
  Future<ChatMessage> _decode(String path, String body) async {
    if (!path.endsWith('.jsonl')) return decodeMessageJson(body);
    final events = const LineSplitter()
        .convert(body)
        .where((line) => line.trim().isNotEmpty)
        .map(decodeEventJson);
    return Stream<ChatEvent>.fromIterable(events).foldToMessage();
  }
}

/// The machine, read off the entity's own `fold`. Never derived: a client that
/// counted messages to guess the state would be a second implementation of it.
final class MachineOverPrimitive implements MachineReader {
  const MachineOverPrimitive(this.primitive);

  final Primitive primitive;

  @override
  Future<Fold> fold(
    Coordinate coord, {
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    final outcome = await primitive.run(
      coord,
      'fold',
      [if (asOf != null) ...['--as-of', asOf.value]],
      vantage: vantage,
    );
    if (outcome.exitCode != 0) {
      throw PrimitiveFailure('fold', outcome.stderr.trim(),
          exitCode: outcome.exitCode);
    }
    final card = jsonDecode(outcome.stdout) as Map<String, dynamic>;
    final commit = card['commit'] as String?;
    return Fold(
      state: _state(card['state'] as String),
      openCalls: [for (final id in card['openCalls'] as List) id as String],
      messages: card['messages'] as int,
      commit: commit == null || commit.isEmpty ? null : Sha(commit),
    );
  }

  SessionState _state(String word) => switch (word) {
        'idle' => SessionState.idle,
        'owes_inference' => SessionState.owesInference,
        'owes_results' => SessionState.owesResults,
        _ => throw PrimitiveFailure('fold', 'unknown state: $word'),
      };
}

/// Which conversation, when nobody typed one.
///
/// Only the first step of the precedence stands: the argument. The variable and
/// the walk up the tree of places are the primitive's convention, and until
/// `entity` answers it this port refuses **naming the front that owes it**.
final class CoordinateOverPrimitive implements CoordinateSource {
  const CoordinateOverPrimitive(this.primitive);

  final Primitive primitive;

  static const String _owed =
      'entity: the ambient coordinate — `entity use`, and the variable name it '
      'spells';

  @override
  Future<CoordinateResolution> resolve(
    String? spelled, {
    Vantage vantage = const Vantage.here(),
  }) async {
    if (spelled == null) throw const OwedByFloor('use', _owed);
    final parts = spelled.split(':');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw CoordinateMalformed(spelled);
    }
    return CoordinateResolution(
      Coordinate(parts.first, parts.last),
      CoordinateOrigin.argument,
    );
  }

  @override
  Future<String> exportLine(Coordinate coordinate) async =>
      throw const OwedByFloor('use', _owed);
}

/// Waiting by folding again and again.
///
/// The mechanism is owed a change — `notify`, a signal to a live process — and
/// this class is where the swap happens when the primitive offers it. Nothing
/// above this interface moves on that day.
final class PollingRest implements Rest {
  const PollingRest(this.machine, {this.every = const Duration(seconds: 1)});

  final MachineReader machine;
  final Duration every;

  @override
  Future<TurnOutcome> awaitRest(
    Coordinate coord, {
    required Duration limit,
    bool Function()? cancelled,
    Vantage vantage = const Vantage.here(),
  }) async {
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) return TurnOutcome.cancelled;
      final fold = await machine.fold(coord, vantage: vantage);
      if (fold.state == SessionState.idle) return TurnOutcome.rested;
      await Future<void>.delayed(every);
    }
    return TurnOutcome.timedOut;
  }
}
