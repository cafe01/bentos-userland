/// The two seams the channel stands on — and they are two because **writing
/// goes through the bodies and reading does not**.
///
/// An act is the entity's own embarked function, run through the primitive:
/// shell over the `entity` coreutil, source and never binary, so the medium
/// installs where no Dart does. A read is a pure tree read, and a process
/// spawned per read makes a live face unusable — so reading happens in process,
/// at a commit, through the primitive's own listing and reading.
///
/// Two readers over one layout, which is affordable exactly because the layout
/// is the contract and neither reader interprets more than it.
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

/// Runs the entity's own functions. The write half.
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
