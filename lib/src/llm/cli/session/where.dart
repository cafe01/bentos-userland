/// Which conversation an invocation is about, and where it resolves from.
///
/// Two steps stand today: the argument, and the ambient variable. The variable's
/// name is **not invented here** — the convention is one variable per ontology,
/// derived mechanically from the entity's own name, so `bentos.llm` gives
/// `BENTOS_LLM`. This file implements a word already spoken, at the wrong floor,
/// temporarily.
///
/// ---------------------------------------------------------------------------
/// ON LOAN — this reading belongs to `entity use`, on the entity primitive's
/// front. When the primitive answers the ambient coordinate, [resolve] becomes a
/// call to the face's own `CoordinateSource` and the third step of the
/// precedence — the walk up the tree of places — arrives with it. Nothing above
/// this file changes on that day.
///
/// Note the layer below never spells this name: `lib/src/llm/session/**` is
/// forbidden it by a standing assertion, and that stays true.
/// ---------------------------------------------------------------------------
library;

import 'dart:io';

import 'package:args/args.dart';

import '../../session/coordinate.dart';
import '../../session/session.dart';

/// The ambient variable's name, **derived** from the ontology and not chosen:
/// one variable per ontology, the dots becoming underscores and the whole
/// upper-cased, so `bentos.llm` gives `BENTOS_LLM`. A mechanical rule has no
/// registry to maintain and no name to pick, which is why it is computed here
/// rather than typed.
final String sessionVariable =
    sessionOntology.replaceAll('.', '_').toUpperCase();

/// The two globals, added to the `session` command's own parser: which
/// conversation, and the place it resolves from. Both are global rather than
/// per-verb — the coordinate is the one thing every invocation shares, and a
/// face that makes a person retype it after the verb is a face nobody uses
/// twice.
void addSessionGlobals(ArgParser parser) {
  parser
    ..addOption(
      'session',
      abbr: 's',
      help: 'The conversation, as <entity>:<instance> or <instance>.\n'
          'Defaults to \$$sessionVariable.',
    )
    ..addOption(
      'at',
      abbr: 'C',
      help: 'The place the coordinate resolves from.\n'
          'Defaults to the vantage you are standing in.',
    );
}

/// The coordinate this invocation acts on.
///
/// The argument wins, the variable answers next, and nothing else is consulted:
/// no stored default, because a register that remembers is a store, and a face
/// owns nothing.
Coordinate coordinateFrom(
  ArgResults? results, {
  String? spelledAs,
  Map<String, String>? environment,
}) {
  final spelled = spelledAs ??
      results?['session'] as String? ??
      (environment ?? Platform.environment)[sessionVariable];
  if (spelled == null || spelled.isEmpty) throw const CoordinateAbsent();
  return parseCoordinate(spelled);
}

/// `<entity>:<instance>`, or a bare `<instance>` against the session ontology —
/// which is only where a caller said nothing, since the face is a face of any
/// body that fuses it.
Coordinate parseCoordinate(String spelled) {
  final parts = spelled.split(':');
  if (parts.length == 1 && parts.single.isNotEmpty) {
    return Coordinate(sessionOntology, parts.single);
  }
  if (parts.length == 2 && parts.every((p) => p.isNotEmpty)) {
    return Coordinate(parts.first, parts.last);
  }
  throw CoordinateMalformed(spelled);
}

/// The place, which `new` needs before any conversation exists.
Vantage vantageFrom(ArgResults? results) {
  final place = results?['at'] as String?;
  return place == null ? const Vantage.here() : Vantage(place);
}
