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

/// The exit code a body uses to say **a gate refused**.
const int bodyRefused = 3;

/// The exit code a body uses to say **the ref moved every time** — `EX_TEMPFAIL`.
const int bodyStumbled = 75;

/// The exit code a body uses for a malformed call — `EX_USAGE`.
const int bodyUsage = 64;

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
const int defaultAttempts = 8;

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

  /// One attempt: opens the private area at the tip, asks [gate] of **that
  /// area** (never of the present tree — the question is *was this act legal
  /// where it lands*), runs [write] when the gate allows it, and lands the
  /// compare-and-swap under [noun] with the legible sentence [say].
  ///
  /// Never retries. [ChatContested] is the caller's cue to attempt again with
  /// a fresh area — the ref simply moved under this one.
  ChatActOutcome attempt(
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
