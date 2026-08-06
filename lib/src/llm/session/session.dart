/// The face: the fourteen methods, over collaborators it does not construct.
///
/// It owns no store, no loop and no state. Writing deposits and falls silent;
/// reading folds at one instant. Nothing here prints — a register is a skin of
/// I/O over this, and none of them is the official one.
library;

import 'package:toml/toml.dart';

import 'coordinate.dart';
import 'face.dart';
import 'machine.dart';
import 'primitive.dart';
import 'transcript.dart';
import 'turn.dart';

/// The ontology this face is a face of. Spellable everywhere it is used — a
/// fused body answers every verb — and this is only where a caller said nothing.
const String sessionOntology = 'bentos.llm';

const String _channelPath = 'llm/channel.toml';
const String _titlePath = 'llm/title';
const String _functionsPath = 'llm/functions';

final class Session implements SessionFace {
  Session({
    required this.primitive,
    required this.coordinates,
    required this.machine,
    required this.transcripts,
    required this.view,
    required this.rest,
  });

  final Primitive primitive;
  final CoordinateSource coordinates;
  final MachineReader machine;
  final TranscriptReader transcripts;
  final TranscriptView view;
  final Rest rest;

  // ── opening and finding ──────────────────────────────────────────────────

  @override
  Future<OpenedSession> open({
    String? name,
    String? entity,
    String? device,
    String? system,
    String? functions,
    Vantage vantage = const Vantage.here(),
  }) async {
    final coord = Coordinate(entity ?? sessionOntology, name ?? _minted());
    await _deposit(
      coord,
      'user.open',
      [
        if (device != null) ...['--device', device],
        if (system != null) ...['--system', system],
        if (functions != null) ...['--functions', functions],
      ],
      vantage: vantage,
    );
    final tip = await primitive.tip(coord, vantage: vantage);
    return OpenedSession(coord, tip ?? const Sha(''));
  }

  @override
  Future<List<SessionCard>> list({
    String? entity,
    Vantage vantage = const Vantage.here(),
  }) async {
    final name = entity ?? sessionOntology;
    final refs = await primitive.instances(name, vantage: vantage);
    final cards = <SessionCard>[];
    for (final ref in refs) {
      final coord = Coordinate(name, ref.instance);
      final acts = await primitive.log(coord, vantage: vantage);
      cards.add(SessionCard(
        coordinate: coord,
        state: (await machine.fold(coord, asOf: ref.tip, vantage: vantage))
            .state,
        title: await readTitle(coord, vantage: vantage),
        lastAct: acts.isEmpty ? null : acts.last,
      ));
    }
    return cards;
  }

  @override
  Future<AmbientReport> use(
    String? spelled, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final resolved = await coordinates.resolve(spelled, vantage: vantage);
    return AmbientReport(
      coordinate: resolved.coordinate,
      origin: resolved.origin,
      // Only a caller that named a coordinate is asking to go there. The line
      // itself is the primitive's to spell, and asking for it is the whole
      // point: a face that built this string would fix a convention it does
      // not own.
      exportLine: spelled == null
          ? null
          : await coordinates.exportLine(resolved.coordinate),
    );
  }

  @override
  Future<String?> readTitle(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    // The one read whose absence is ordinary: a conversation nobody named has
    // no such path, and that is a null title rather than a broken session.
    // Every other read in this face fails loudly.
    try {
      final text = await primitive.read(coord, _titlePath, vantage: vantage);
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } on PrimitiveFailure {
      return null;
    }
  }

  @override
  Future<Deposited> setTitle(
    Coordinate coord,
    String text, {
    Vantage vantage = const Vantage.here(),
  }) =>
      _deposit(coord, 'user.title', [text], vantage: vantage);

  // ── speaking ─────────────────────────────────────────────────────────────

  @override
  Future<TurnResult> say(
    Coordinate coord,
    String text, {
    bool wait = true,
    Duration limit = const Duration(seconds: 180),
    Lens lens = Lens.conversation,
    bool Function()? cancelled,
    Vantage vantage = const Vantage.here(),
  }) async {
    final from = await primitive.tip(coord, vantage: vantage);
    final landed = await primitive.run(
      coord,
      'user.say',
      [text],
      vantage: vantage,
    );

    // A refusal is a value and it is the floor's own words. Nothing was
    // deposited, so there is nothing to wait for.
    if (landed.exitCode != 0) {
      return TurnResult(
        outcome: TurnOutcome.refused,
        landed: const [],
        from: from,
        to: from,
        refusal: landed.stderr.trim(),
      );
    }

    if (!wait) {
      return TurnResult(
        outcome: TurnOutcome.rested,
        landed: const [],
        from: from,
        to: await primitive.tip(coord, vantage: vantage),
      );
    }

    final outcome = await rest.awaitRest(
      coord,
      limit: limit,
      cancelled: cancelled,
      vantage: vantage,
    );
    final to = await primitive.tip(coord, vantage: vantage);
    return TurnResult(
      outcome: outcome,
      // Whatever the wait's verdict, what landed is shown: a timeout ran out
      // of patience, not out of work.
      landed: _since(
        view.render(
          await transcripts.transcript(coord, asOf: to, vantage: vantage),
          lens,
        ),
      ),
      from: from,
      to: to,
    );
  }

  /// What the session gained since the person last spoke. Their own words are
  /// left out — they have just typed them, and echoing them back is padding.
  List<RenderedTurn> _since(List<RenderedTurn> turns) {
    final mine = turns.lastIndexWhere((t) => t.speaker == Speaker.you);
    return mine < 0 ? turns : turns.sublist(mine + 1);
  }

  @override
  Future<Deposited> result(
    Coordinate coord,
    String callId,
    String text, {
    bool failed = false,
    Vantage vantage = const Vantage.here(),
  }) async =>
      throw const OwedByFloor(
        'result',
        'bentos.llm: user.result <call-id> <text> [--failed] — a deposit for a '
            'result nobody ran',
      );

  // ── seeing ───────────────────────────────────────────────────────────────

  @override
  Future<Screen> show(
    Coordinate coord, {
    Lens lens = Lens.conversation,
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  }) async {
    // One tip per screen, and everything below descends with it. A transcript
    // read at one instant under a state read at the next describes a session
    // that never existed.
    final pinned = asOf ?? await primitive.tip(coord, vantage: vantage);
    if (pinned == null) throw SessionNotOpen(coord);

    return Screen(
      pinnedAt: pinned,
      lens: lens,
      turns: view.render(
        await transcripts.transcript(coord, asOf: pinned, vantage: vantage),
        lens,
      ),
      fold: await machine.fold(coord, asOf: pinned, vantage: vantage),
      acts: lens == Lens.audit
          ? await primitive.log(coord, vantage: vantage)
          : const [],
    );
  }

  @override
  Future<int> monitor(
    Coordinate coord, {
    Lens lens = Lens.conversation,
    Vantage vantage = const Vantage.here(),
  }) =>
      primitive.attach(
        coord,
        'user.monitor',
        ['--lens', lens.name],
        vantage: vantage,
      );

  @override
  Future<StatusLine> status({Vantage vantage = const Vantage.here()}) async {
    final Coordinate coord;
    try {
      coord = (await coordinates.resolve(null, vantage: vantage)).coordinate;
    } on Exception {
      // Nowhere is a state a prompt has to be able to show, and every way of
      // being nowhere — absent, ambiguous, or a convention the floor still
      // owes — reads the same from a shell prompt.
      return const StatusLine(state: SessionState.idle);
    }
    final fold = await machine.fold(coord, vantage: vantage);
    return StatusLine(
      state: fold.state,
      coordinate: coord,
      title: await readTitle(coord, vantage: vantage),
    );
  }

  // ── travelling in time ───────────────────────────────────────────────────

  @override
  Future<OpenedSession> fork(
    Coordinate coord, {
    Sha? at,
    String? name,
    Vantage vantage = const Vantage.here(),
  }) async {
    final from = at ?? await primitive.tip(coord, vantage: vantage);
    if (from == null) throw SessionNotOpen(coord);
    // A second conversation, born at the act. The one forked from is not
    // touched, which is what makes both continuations stand.
    final born = Coordinate(coord.entity, name ?? _minted());
    final tip = await primitive.birth(born, from: from, vantage: vantage);
    return OpenedSession(born, tip, bornFrom: from);
  }

  @override
  Future<Deposited> revise(
    Coordinate coord, {
    required String message,
    required String text,
    Vantage vantage = const Vantage.here(),
  }) =>
      _deposit(
        coord,
        'user.revise',
        ['--from', message, text],
        vantage: vantage,
      );

  @override
  Future<Deposited> reviseConstitution(
    Coordinate coord,
    String text, {
    Vantage vantage = const Vantage.here(),
  }) =>
      _deposit(coord, 'user.revise', ['--system', text], vantage: vantage);

  @override
  Future<Deposited> rewind(
    Coordinate coord,
    String message, {
    Vantage vantage = const Vantage.here(),
  }) async =>
      throw const OwedByFloor(
        'rewind',
        'bentos.llm: user.revise --from <message> --drop — undoing is not '
            'rewriting, and revise demands new text',
      );

  // ── tuning ───────────────────────────────────────────────────────────────

  @override
  Future<List<Knob>> knobs(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final channel = await primitive.read(coord, _channelPath, vantage: vantage);
    final document = TomlDocument.parse(channel).toMap();
    return [
      for (final entry in document.entries)
        // Every knob reports as offered: gating is owed, a device does not
        // announce its capabilities yet, and a knob reported as refused today
        // would be a guess wearing the authority of a report.
        Knob(entry.key, entry.value?.toString()),
    ];
  }

  @override
  Future<Deposited> tune(
    Coordinate coord,
    Map<String, String> changes, {
    Vantage vantage = const Vantage.here(),
  }) =>
      _deposit(
        coord,
        'user.tune',
        [for (final c in changes.entries) '${c.key}=${c.value}'],
        vantage: vantage,
      );

  @override
  Future<List<PluggedFunction>> plugged(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  }) async {
    final paths = await primitive.ls(coord, _functionsPath, vantage: vantage);
    final names = <String>{};
    final bodies = <String>{};
    for (final path in paths) {
      final leaf = path.split('/').last;
      if (leaf.isEmpty || leaf.startsWith('.')) continue;
      if (leaf.endsWith('.json')) {
        names.add(leaf.substring(0, leaf.length - '.json'.length));
      } else {
        bodies.add(leaf);
      }
    }
    return [
      for (final name in names.toList()..sort())
        // A definition with no executable beside it is a legal session: the
        // call comes back and the executor answers that there is no such
        // function.
        PluggedFunction(name, implemented: bodies.contains(name)),
    ];
  }

  @override
  Future<Deposited> plug(
    Coordinate coord,
    String definition, {
    String? executable,
    Vantage vantage = const Vantage.here(),
  }) =>
      _deposit(
        coord,
        'user.plug',
        [definition, ?executable],
        vantage: vantage,
      );

  // ── the one way anything is written ──────────────────────────────────────

  /// Every deposit goes through here: run the entity's own function, and read
  /// what it landed. The commit is on stdout, the sentence beside it on stderr,
  /// and any non-zero exit is a refusal **in the floor's own words** — never
  /// paraphrased, and never turned into an error of ours.
  Future<Deposited> _deposit(
    Coordinate coord,
    String function,
    List<String> arguments, {
    required Vantage vantage,
  }) async {
    final outcome =
        await primitive.run(coord, function, arguments, vantage: vantage);
    if (outcome.exitCode != 0) {
      throw PrimitiveFailure(function, outcome.stderr.trim(),
          exitCode: outcome.exitCode);
    }
    final sentence = outcome.stderr.trim();
    return Deposited(
      Sha(outcome.stdout.trim()),
      sentence: sentence.isEmpty ? null : sentence,
    );
  }

  /// A name for a conversation nobody named. Ordered by time, because a listing
  /// of them is read as a history.
  String _minted() => DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]|\.\d+Z$'), '')
      .toLowerCase();
}
