/// The two seams the channel stands on — and they are two because **writing
/// goes through an act bracket and reading does not**.
///
/// An act opens the entity's own private area **in process**, through the
/// primitive's Dart API — no shell, no spawn: the retry loop that used to live
/// in the entity's embarked body now lives here, once, and the library owns
/// the bound. A read is a pure tree read, and a process spawned per read makes
/// a live face unusable — so reading happens in process too, at a commit,
/// through the primitive's own listing and reading.
///
/// Two readers over one layout, which is affordable exactly because the layout
/// is the contract and neither reader interprets more than it.
///
/// [ChatBodies] survives for one function only: `check`, the author-signature
/// gate, which is not a [Channel] method and still runs the entity's own
/// declared function through the primitive.
library;

/// What running a body returned.
final class BodyOutcome {
  const BodyOutcome({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

// The exit codes a *body* uses are gone from here, and the deletion is the
// point rather than a tidy-up. `bodyRefused`, `bodyStumbled` and `bodyUsage`
// described what an entity's shell bodies exit — `<entity>/bin/*.sh`, a shape
// the platform has since abandoned. Two of the three were read by nobody, and
// the third was only lending its value to `ChatRunner.stumbledCode`, which now
// states 75 beside the five codes it already owned.
//
// The comment that stood here declared `bodyRefused = 3` false, having measured
// it against `bin/lib.sh` and found `return 1`. The value was right and the
// authority was wrong: 3 is *barred* in the entity's own contract, and what the
// shell bodies did was fail to adopt it. A claim nobody could exercise, checked
// against a concept on its way out, and quoted downstream as law.

/// The environment variable the bodies read their retry bound from.
///
/// **The retry lives in the body, and there is exactly one of it.** `lib.sh`
/// loops, minting the ULID before the loop so every attempt writes the same
/// bytes at the same path, and re-asking the gate inside it against the area
/// cut from the tip that attempt will swap against. A second loop in this
/// library would multiply the bound and make [Stumbled.attempts] a lie — so
/// what the library owns is not the retrying but **the bound**, handed down
/// here and reported back unchanged.
const String attemptsVariable = 'BENTOS_CHAT_ATTEMPTS';

/// What the body defaults to when nobody sets [attemptsVariable].
///
/// **Read off a measured distribution, not chosen.** Eight carried a quiet
/// machine and dropped roughly one line in eight under a loaded one, and a
/// joiner that exhausted it stayed outside and was refused for everything it
/// then said. The measurement, 12/08/2026, with the storm gate's own writers —
/// four of them, six lines each, the whole material suite running its files at
/// once for load — set the bound deliberately at 64 so the demand could be
/// *read* rather than truncated: eight storms, 224 acts, every one landed, and
/// the attempts each needed peaked per storm at 7, 8, 8, 8, 9, 9, 10 and 11.
/// So 8 sat below the observed worst case, which is exactly why it failed
/// intermittently; 24 is a little over double it.
///
/// The headroom is cheap and asymmetric: a bound is only ever spent by an act
/// that keeps losing, so a wider one costs nothing on a quiet channel and costs
/// a lost line on a busy one. What makes a number this size *sufficient* rather
/// than merely large is the backoff under it — `LocalChannel._act` waits full
/// jitter, uniform in `[0, 100ms · 2^(n-1)]` capped at four seconds, so
/// repeated collision decays instead of repeating. Under the flat wait it
/// replaced the tail was geometric and no bound removed it.
///
/// **What it costs is latency, and the cost is measured too**: in the same
/// storms most acts finished inside three seconds and the ones that lost seven
/// to nine races took 7–11, since a retry that waits is a caller that waits. A
/// dropped line traded for a slow line is the right trade for a medium a
/// factory coordinates in, and a quiet channel pays none of it — but the knob
/// that governs the trade is the backoff cap, not this number, and whether a
/// tighter cap buys back the tail without raising the demand is **unmeasured
/// and owed**.
///
/// Re-measure it, never re-guess it: raise the gate's bound, run the storms
/// under load, and read `StormVerdict.describe()`'s first two lines.
const int defaultAttempts = 24;

/// Runs the entity's own declared functions through the primitive. What
/// survives of the shell face's spawn-and-map-exit-codes seam, kept for
/// `check` alone — a gate, not a [Channel] method, with no [ChatActs] bracket
/// of its own to open.
abstract interface class ChatBodies {
  /// `entity -C <place> run <coord> <function> [args]`, with [attemptsVariable]
  /// set to [attempts] in the child's environment.
  ///
  /// It does not interpret the outcome: the exit code comes back as the body
  /// spelled it, and mapping it to an [ActResult] is the channel's job — one
  /// place, so that every verb answers a lost race the same way.
  Future<BodyOutcome> run(
    String function,
    List<String> arguments, {
    required int attempts,
  });
}

/// Opens the act bracket **in process**, and lands one attempt of it.
///
/// One attempt, never a loop: [LocalChannel] owns the bound and the retrying,
/// so that the bound it hands down and the attempts a caller can count are the
/// same number. A second loop behind this seam would double both, silently.
abstract interface class ChatActs {
  /// Whether the channel exists yet — the ref born or not.
  bool get born;

  /// Births the ref at the class's own empty structure. Idempotent: does
  /// nothing where [born] already holds. The one door in — every other verb
  /// finds an unborn channel by [attempt] refusing to open an area at all.
  void ensureBorn();

  /// One attempt: asks [gate] of the instance's own standing tree, runs
  /// [write] there when the gate allows it, and lands the act under [noun]
  /// with the legible sentence [say].
  ///
  /// Never retries. [ChatContested] is the caller's cue to attempt again —
  /// **kept in the type for a caller of this interface to handle, not
  /// because an entity-backed implementation can still produce it.** The
  /// private area and its compare-and-swap are retired; an act now commits
  /// where the instance already stands, one attached tree per instance, and
  /// there is no swap left to lose. An implementation that still opens a
  /// private area per attempt may return it honestly.
  Future<ChatActOutcome> attempt(
    String noun, {
    required void Function(ChatArea area) write,
    String? Function(ChatArea area)? gate,
    String? say,
  });
}

/// The private area one attempt writes into — file IO under the layout, and
/// nothing else. Existing content is already there: an area is a
/// materialization of the tip, not an empty scratch directory.
abstract interface class ChatArea {
  void write(String path, String content);

  /// Removes the file or directory at [path], recursively.
  void removeTree(String path);

  /// Whether a file or directory stands at [path].
  bool exists(String path);

  /// The bytes at [path] as text, or null where nothing stands there.
  ///
  /// **A gate that must compare needs to read.** Arrival asks what address
  /// already holds a seat, and asking the tree outside the bracket would ask a
  /// state the swap never demanded — which is the race, one floor below the
  /// compare-and-swap.
  String? read(String path);
}

/// What one attempt at [ChatActs.attempt] returned.
sealed class ChatActOutcome {
  const ChatActOutcome();
}

/// The act became true, at [commit].
final class ChatLanded extends ChatActOutcome {
  const ChatLanded(this.commit);
  final String commit;
}

/// [gate] said no — a decision, never retried.
final class ChatGateRefused extends ChatActOutcome {
  const ChatGateRefused(this.reason);
  final String reason;
}

/// The ref moved under this attempt. Nobody decided anything.
final class ChatContested extends ChatActOutcome {
  const ChatContested();
}

/// One act of this channel, as the log holds it.
final class ChatAct {
  const ChatAct({
    required this.commit,
    required this.noun,
    required this.authorEmail,
    required this.authorName,
    required this.instant,
    this.sentence,
  });

  final String commit;

  /// The noun the act deposited — the only word the floor reads.
  final String noun;

  final String authorEmail;
  final String authorName;
  final DateTime instant;

  /// The legible sentence, stored and printed and never interpreted.
  final String? sentence;
}

/// Reads the channel's tree and log, in process. The read half.
///
/// Every read answers **at a point in history**, because a gate stands at the
/// parent of the act landing and that is never the present.
abstract interface class ChatTree {
  /// The commit this channel stands at, or null until it is born.
  String? tip();

  /// The bytes at [path], decoded, or null when the path is not there — which
  /// is ordinary: a participant who declared no display name simply has no such
  /// file.
  String? read(String path, {String? at});

  /// The paths one level under [path], sorted. Empty when there is no such
  /// directory.
  List<String> ls(String path, {String? at});

  /// The acts, **newest first**, as the substrate reports them.
  List<ChatAct> log();

  /// The paths [commit] added. What a `message` act deposited is the path it
  /// added, so a reader of the transcript never has to know the layout.
  List<String> added(String commit);
}
