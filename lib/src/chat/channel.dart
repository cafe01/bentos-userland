/// The caller's surface: a channel, and the laws that govern it.
///
/// It mirrors the entity's verbs and **adds nothing**. The object comes by
/// argument and there is no seat prefix, the ontology having exactly one seat —
/// `say` is the whole name, and who spoke is the author on the commit rather
/// than a word in the verb.
library;

import 'handle.dart';
import 'model.dart';
import 'outcome.dart';

// The names live in a leaf so the layers beneath this one may say them too, and
// are re-exported here because this is where a caller looks for them.
export 'ontology.dart';

/// A conversation, from the outside.
///
/// A handle: opening one creates nothing and reads nothing, and a ref moved by
/// another participant is seen on the next call.
abstract interface class Channel {
  /// The channel's name within the ontology — the second half of its
  /// coordinate, and the word a person joins.
  ///
  /// The instance id, which is always true and costs nothing. The spec's
  /// `chat/name` has no function that writes it and no body that deposits one;
  /// until it does, it is a frontier and not this surface's business.
  String get name;

  /// The coordinate whole: `bentos.chat:<name>`.
  String get coordinate;

  /// The handle this caller acts under — the substrate's, never an argument.
  Handle get me;

  // ── reading ──────────────────────────────────────────────────────────────
  //
  // Every read answers **at a point in history**, and `at` is how a caller says
  // which one: a commit of this line, or its unambiguous prefix, defaulting to
  // the present. Not a convenience — a gate stands at the parent of the act
  // landing and asks whether that act was legal *there*, which is never now, and
  // a surface that could only see the present would push every historical
  // reading back below the ontology. It is a named argument rather than a field
  // of the coordinate because whether the address itself should carry a point in
  // history is the ontology's open question and not this surface's to answer.

  /// The current topic, or null when nobody has set one.
  ///
  /// It keeps no history of its own: the log of that one file is its history,
  /// author and time included.
  Future<String?> topic({String? at});

  /// Who is in the channel — one listing, never a walk over the log.
  Future<Roster> roster({String? at});

  /// The transcript, **in the order of the log**, which is the order it
  /// arrived. Not the order the ULIDs sort in: the time inside a message is
  /// when it was spoken, its position is when it landed, and on two machines
  /// those are different facts.
  ///
  /// [since] and [until] filter on the spoken time; [limit] takes the last [n]
  /// to arrive. Paging by the date partition is a seam the layout leaves open
  /// and this surface does not yet exploit.
  Future<List<Message>> history({
    DateTime? since,
    DateTime? until,
    int? limit,
    String? at,
  });

  // ── acting ───────────────────────────────────────────────────────────────

  /// Enter. **Idempotent by reading the tree and never by remembering**:
  /// reconnecting is ordinary and a client must not have to know whether it
  /// already entered. It opens the channel when the channel does not exist yet
  /// — membership is the only door in.
  Future<ActResult> join({String? displayName});

  /// Leave. The seat is torn down whole; **what was said stays said**.
  ///
  /// The roster answers *who is here* and the transcript answers *what was
  /// said*, so a departed participant vanishes from the first and remains in
  /// the second. That is the two questions being different and not an
  /// inconsistency, and it is written here because it reads as a bug to
  /// whoever meets it first.
  ///
  /// Not idempotent, unlike [join]: leaving a channel you are not in is
  /// refused, because it is a mistake rather than a reconnection.
  Future<ActResult> leave();

  /// Speak. **The one gate of this application**: only a member may speak.
  /// Reading is repository access and the application defends nothing there.
  Future<ActResult> say(String body);

  /// Change the topic — which is writing one file. **It keeps no history of
  /// its own**: the log of that path is its history, author and time included,
  /// and each commit touching it is a segment boundary.
  Future<ActResult> setTopic(String text);

  /// Declare yourself away, with an optional reason.
  ///
  /// **Presence is declared or absent, never simulated.** The medium has no
  /// clock on anybody: what it holds is what somebody said about themselves.
  /// A null reason and an empty one are the same act — *away, having said
  /// nothing* is a declaration, and [Participant.away] distinguishes it from
  /// presence by the path and not by the bytes.
  ///
  /// **A participant may only move itself.** This and [back], [join] and
  /// [leave] operate on the caller's own handle, derived from the commit
  /// identity — never on a handle passed as an argument. Nothing in this
  /// surface can put words or states on anybody else.
  Future<ActResult> away([String? reason]);

  /// Declare yourself back — the field ceasing to exist rather than a value
  /// meaning *present*, since a `here` written into a file would be a second
  /// way of spelling the absence of one.
  Future<ActResult> back();

  // ── watching ─────────────────────────────────────────────────────────────

  /// Everything that has landed since the cursor, in log order; advances it.
  ///
  /// **The cursor is never committed.** It is local like an unread mark, no
  /// participant learns another's, and the medium has no notion that anyone is
  /// reading at all. A channel opened at a last-seen commit resumes there; one
  /// opened at nothing sees the conversation whole.
  ///
  /// How often this is called is the caller's business: *live* is a cadence a
  /// client chooses, and there is nothing for an inert medium to do about it.
  Future<List<ChannelEvent>> sync();

  /// Where the cursor stands — what a client persists if it wants to resume.
  String? get cursor;

  /// Blocks until something qualifying lands, or [within] expires — **the
  /// one wait every face needs**, so a screen, a script and a model all reach
  /// this instead of each growing its own doorbell.
  ///
  /// [mentioning] narrows what qualifies to speech naming that handle's
  /// local part (or everyone); null means any event qualifies. It carries no
  /// content: the cursor is untouched until the caller reads the batch with
  /// [sync], so the two axes stay one mechanism and the cursor keeps its
  /// single owner. A burst that lands together — several messages, a replay
  /// — settles briefly and returns as one waking rather than one per line.
  ///
  /// **A participant is never woken by their own speech.** This asks *did
  /// anyone else speak*, not *did anything land*: a [Spoke] authored by [me]
  /// never qualifies, mentioning it or not. The caller's own utterance is
  /// still there for their own [sync] once this returns — nothing is
  /// dropped, only excluded from what wakes the wait.
  ///
  /// A doorbell outage is answered too, not swallowed: if nothing has
  /// qualified yet and the ticker reports itself down, this future
  /// completes with [DoorbellDown] instead of a value — a stumbled
  /// connection is not a decided [Arrival] and must never read as one, so it
  /// takes the one channel a value can never occupy: the error side of the
  /// same future.
  Future<Arrival> wait({Duration? within, String? mentioning});
}

/// What [Channel.wait] answers. Never content — the caller reads that with
/// [Channel.sync].
enum Arrival { landed, expired }

/// Thrown by [Channel.wait] instead of returning when the doorbell reports
/// itself down before anything qualifying landed. Distinct from
/// [Arrival.expired]: expired says nothing happened, this says the wait
/// could not tell whether anything did.
final class DoorbellDown implements Exception {
  const DoorbellDown();

  @override
  String toString() => 'DoorbellDown: the dispatch doorbell is disconnected';
}
