/// `llm session` — the face, as an ontology rather than as a command line.
///
/// The verbs here are the product: designing this set is designing the buttons
/// of the graphical sibling, and what is not here will exist in no register.
/// Every method returns what happened; **nothing here prints**. A register is a
/// skin of I/O over this interface — the scripted line, the shell as a REPL, the
/// TUI, the window — and none of them is the official one.
///
/// Fifteen verbs, fourteen methods: `repl` is the interactive register and is
/// composed of [show] and [say] rather than being a verb of its own. It is
/// explicit and never the default, because a loop of our own is one register
/// among others and the loop that matters belongs to the shell.
library;

import 'coordinate.dart';
import 'machine.dart';
import 'primitive.dart';
import 'transcript.dart';
import 'turn.dart';

/// A write landed: one act, one commit.
final class Deposited {
  const Deposited(this.sha, {this.sentence});

  final Sha sha;

  /// The act's own sentence, as the log will show it.
  final String? sentence;
}

/// A conversation now exists — freshly opened, or forked from a live commit.
final class OpenedSession {
  const OpenedSession(this.coordinate, this.tip, {this.bornFrom});

  final Coordinate coordinate;
  final Sha tip;

  /// The commit it was born from. Null is genesis, which is a new conversation;
  /// anything else is a fork, and both continuations stand.
  final Sha? bornFrom;
}

/// One conversation in a listing.
final class SessionCard {
  const SessionCard({
    required this.coordinate,
    required this.state,
    this.title,
    this.lastAct,
  });

  final Coordinate coordinate;
  final SessionState state;
  final String? title;

  /// The last act, which is what makes a listing readable as *where things
  /// stand* rather than as a directory.
  final Act? lastAct;
}

/// The answer to *which conversation am I in* — and, when a coordinate was
/// named, the line a shell evaluates to get there.
final class AmbientReport {
  const AmbientReport({
    required this.coordinate,
    required this.origin,
    this.exportLine,
  });

  final Coordinate coordinate;
  final CoordinateOrigin origin;
  final String? exportLine;
}

/// What a person spent, folded from the turns that carry it.
final class TokenSpend {
  const TokenSpend(this.input, this.output);

  final int input;
  final int output;
}

/// The one-line fold a shell prompt calls at every keystroke of Enter. It reads
/// the tree and never the network, which is what makes it affordable there.
final class StatusLine {
  const StatusLine({
    required this.state,
    this.coordinate,
    this.title,
    this.spend,
  });

  final SessionState state;

  /// Null when no step of the precedence answered — the honest report of a shell
  /// that is in no conversation.
  final Coordinate? coordinate;
  final String? title;

  /// Null when the transcript carries no usage.
  final TokenSpend? spend;
}

/// A screen: one reading, one commit.
///
/// **Everything below [pinnedAt] was read there.** A transcript read at one
/// instant and a state read at the next describe a session that never existed,
/// which is how a screen once printed a prompt with no reply under the word
/// `idle`.
final class Screen {
  const Screen({
    required this.pinnedAt,
    required this.lens,
    required this.turns,
    required this.fold,
    this.acts = const [],
  });

  final Sha pinnedAt;
  final Lens lens;
  final List<RenderedTurn> turns;
  final Fold fold;

  /// Populated under [Lens.audit] only: the primitive's own log, unretold.
  final List<Act> acts;
}

/// One knob of the channel, and whether the device standing behind this session
/// will honour it.
final class Knob {
  const Knob(this.key, this.value, {this.offered = true, this.refusedBecause});

  final String key;
  final String? value;

  /// False when the device does not announce this capability. The knob is shown
  /// with its reason rather than hidden: a panel that hides teaches nothing.
  final bool offered;
  final String? refusedBecause;
}

/// A function plugged into the conversation.
final class PluggedFunction {
  const PluggedFunction(this.name, {required this.implemented});

  final String name;

  /// False when only the definition landed: the call will come back and the
  /// executor will answer that there is no such function. That is a legal
  /// session — a function offered by a site that does not run it.
  final bool implemented;
}

/// The coordinate names no conversation that has been born.
///
/// A distinct type because it is the one failure a register answers with an
/// instruction rather than with an error: the conversation is not broken, it has
/// not been opened.
final class SessionNotOpen implements Exception {
  const SessionNotOpen(this.coordinate);
  final Coordinate coordinate;
}

/// Raised by a verb whose mechanics the floor still owes, naming the piece.
///
/// It exists so the gate can assert the seam rather than skip it: the red names
/// the missing verb, and the day that verb lands the same test goes green with
/// nothing edited here.
final class OwedByFloor implements Exception {
  const OwedByFloor(this.verb, this.owed);

  /// The face verb that cannot stand yet.
  final String verb;

  /// The piece that is missing, spelled as the floor will spell it — e.g.
  /// `bentos.llm: user.revise --from <message> --drop`.
  final String owed;

  /// The debt, spelled where a person reads it. Without this the standing red
  /// in CI says `Instance of 'OwedByFloor'` and names nothing — a seam that
  /// reports its own existence and not its content, which is half a seam.
  @override
  String toString() => 'llm session $verb: owed by the floor — $owed';
}

/// How the suite reaches an implementation without naming one.
///
/// The construction delivery exposes exactly one of these, and it is the whole
/// seam between the two chairs: every collaborator arrives through it, so the
/// gate plugs a double in place of each and no test knows a concrete class —
/// which is what lets the suite, written first and unedited after, judge the
/// delivery.
///
/// Each layer is reachable on its own, because each is judged on its own: the
/// pure pieces with no double at all, the readers over a fake primitive, the
/// face over doubled readers.
abstract interface class SessionConstruction {
  /// The attribution rule and the lens: pure, and answerable with no
  /// collaborator whatsoever.
  Attribution get attribution;
  TranscriptView get view;

  /// The readers, over whatever primitive is handed to them.
  MachineReader machineOver(Primitive primitive);
  TranscriptReader transcriptsOver(Primitive primitive);
  CoordinateSource coordinatesOver(Primitive primitive);

  /// Waiting, over the machine it folds.
  Rest restOver(MachineReader machine);

  /// The face itself, over collaborators the caller chooses.
  SessionFace face({
    required Primitive primitive,
    required CoordinateSource coordinates,
    required MachineReader machine,
    required TranscriptReader transcripts,
    required TranscriptView view,
    required Rest rest,
  });
}

/// The fourteen methods. Argument names are the product's words; the functions
/// they reach are the entity's, and the mapping is stated on each.
abstract interface class SessionFace {
  // ── opening and finding ────────────────────────────────────────────────

  /// `new` — a conversation begins. Reaches `user.open` at a coordinate that is
  /// not yet born, which is the one asymmetry of the seat: external will has to
  /// enter the graph somewhere.
  ///
  /// [system] is the constitution, as text. A real one does not fit in argv, so
  /// a register takes a path from the person and hands the contents here —
  /// reading a file is I/O, which is the skin's job and never the face's.
  Future<OpenedSession> open({
    String? name,
    String? entity,
    String? device,
    String? system,
    String? functions,
    Vantage vantage = const Vantage.here(),
  });

  /// `ls` — the conversations standing in a place, each with its title, its
  /// state and its last act.
  Future<List<SessionCard>> list({
    String? entity,
    Vantage vantage = const Vantage.here(),
  });

  /// `use` — the ambient coordinate. With [spelled], the export line a shell
  /// evaluates; without it, where the caller already is and which step said so.
  ///
  /// Owed by the floor until `entity` answers the ambient convention: the face
  /// spells no variable name of its own.
  Future<AmbientReport> use(
    String? spelled, {
    Vantage vantage = const Vantage.here(),
  });

  /// `title` — read the conversation's name, or set it through `user.title`.
  Future<String?> readTitle(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  });

  Future<Deposited> setTitle(
    Coordinate coord,
    String text, {
    Vantage vantage = const Vantage.here(),
  });

  // ── speaking ───────────────────────────────────────────────────────────

  /// `say` — deposit a prompt through `user.say` and, unless [wait] is false,
  /// follow the circuit to rest and answer with what landed.
  Future<TurnResult> say(
    Coordinate coord,
    String text, {
    bool wait = true,
    Duration limit = const Duration(seconds: 180),
    Lens lens = Lens.conversation,
    bool Function()? cancelled,
    Vantage vantage = const Vantage.here(),
  });

  // `result` stood here, and it is deleted rather than deferred. It offered a
  // person the executor's seat and declared `bentos.llm: user.result` owed for
  // it — a function that does not exist and must not: the manifest declares
  // twelve, and the deposit for a call's outcome is `executor.run`'s
  // `function-result`. **The act is the executor's.** Who occupies that seat —
  // a program, or a person typing by hand in a playground — is an application's
  // affair, and no ontology verb is minted for the second case. A face that
  // wants a hand-typed result deposits as the executor and signs it as itself.

  // ── seeing ─────────────────────────────────────────────────────────────

  /// `show` — the screen, pinned. [asOf] reads an older instant; absent, the tip
  /// is taken once and everything descends with it.
  Future<Screen> show(
    Coordinate coord, {
    Lens lens = Lens.conversation,
    Sha? asOf,
    Vantage vantage = const Vantage.here(),
  });

  /// `monitor` — the live register: reaches `user.monitor`, which registers a
  /// body against every landing and writes as the conversation moves. Returns
  /// when the person stops looking; the circuit is untouched either way.
  Future<int> monitor(
    Coordinate coord, {
    Lens lens = Lens.conversation,
    Vantage vantage = const Vantage.here(),
  });

  /// `status` — the one-line fold, for a shell prompt. Answers even when no
  /// coordinate resolves, because *nowhere* is a state a prompt must show.
  Future<StatusLine> status({Vantage vantage = const Vantage.here()});

  // ── travelling in time ─────────────────────────────────────────────────

  /// `fork` — a second conversation born at an act, both continuations
  /// standing. Reaches the primitive's own constructor with `--from`.
  Future<OpenedSession> fork(
    Coordinate coord, {
    Sha? at,
    String? name,
    Vantage vantage = const Vantage.here(),
  });

  /// `revise` — a past turn rewritten and run on from there, through
  /// `user.revise`. Destructive by construction: what followed is discarded, and
  /// the machine is read off what remains.
  Future<Deposited> revise(
    Coordinate coord, {
    required String message,
    required String text,
    Vantage vantage = const Vantage.here(),
  });

  /// `revise --system` — the leading message amended, the conversation
  /// standing.
  Future<Deposited> reviseConstitution(
    Coordinate coord,
    String text, {
    Vantage vantage = const Vantage.here(),
  });

  // `rewind` stood here and is deleted, for the reason `result` was: it named
  // *what* an edit did — discard from here on, without rewriting — where the
  // entity only registers *that* the transcript changed. `user.revise` covers
  // it entirely and means exactly that much; whether an application let someone
  // drag a ruler up the history, drop everything under it and fire inference
  // again is the application's ontology, and the entity neither knows nor
  // should. The context window sent to inference is the whole transcript, so an
  // application that wants a different one revises the transcript and says
  // nothing about its motive.

  // ── tuning ─────────────────────────────────────────────────────────────

  /// `tune` — with no changes, the channel as it stands, each knob carrying
  /// whether the device offers it. With changes, one act through `user.tune`,
  /// landing before the turn it tunes.
  ///
  /// The gating half is owed: a device does not yet announce its capabilities,
  /// so every knob reports as offered until it does.
  Future<List<Knob>> knobs(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  });

  Future<Deposited> tune(
    Coordinate coord,
    Map<String, String> changes, {
    Vantage vantage = const Vantage.here(),
  });

  /// `plug` — a function entering the conversation through `user.plug`, or the
  /// list of what is already plugged.
  Future<List<PluggedFunction>> plugged(
    Coordinate coord, {
    Vantage vantage = const Vantage.here(),
  });

  Future<Deposited> plug(
    Coordinate coord,
    String definition, {
    String? executable,
    Vantage vantage = const Vantage.here(),
  });
}
