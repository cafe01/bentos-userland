/// What comes back from acting, and what comes back from watching.
library;

import 'handle.dart';
import 'ontology.dart';
import 'model.dart';

/// The outcome of an act. **A refusal is a value, never an exception**, and
/// sealed so the caller cannot forget the branch.
sealed class ActResult {
  const ActResult();
}

/// It landed, at [commit].
final class Acted extends ActResult {
  const Acted(this.commit);

  final String commit;
}

/// Somebody decided no. [reason] is **the floor's own words**, never
/// paraphrased and never turned into an error of ours.
///
/// Reserved for the membership gate and for a line that genuinely diverged on
/// fetch. A gate refusal exits at once and is never retried: retrying a
/// decision would turn a clear no into a confused wait.
final class Refused extends ActResult {
  const Refused(this.reason);

  final String reason;
}

/// The channel is moving faster than this writer can land in it.
///
/// **Nobody decided anything.** The act's swap lost its race [attempts] times
/// running, each attempt a fresh reading of the world, and the honest answer is
/// *try again* rather than *no*. Distinguishing this from [Refused] is what
/// keeps a busy channel from reading as a hostile one.
final class Stumbled extends ActResult {
  const Stumbled(this.attempts);

  /// How many attempts the writer was given — the bound this caller set, not a
  /// count scraped from a message.
  final int attempts;
}

/// Something that landed since the cursor.
sealed class ChannelEvent {
  const ChannelEvent();
}

final class Spoke extends ChannelEvent {
  const Spoke(this.message);

  final Message message;
}

final class TopicChanged extends ChannelEvent {
  const TopicChanged(this.topic, this.by);

  final String topic;
  final Handle by;
}

/// Membership or presence moved. It carries the roster **as read at the end of
/// the batch** rather than a difference: the roster is one listing, and folding
/// a diff out of the log is the expense the materialized layout exists to
/// avoid.
final class RosterChanged extends ChannelEvent {
  const RosterChanged(this.roster);

  final Roster roster;
}

/// The channel does not exist. Not a refusal — there was nothing to refuse.
final class NoSuchChannel implements Exception {
  const NoSuchChannel(this.coordinate);

  final String coordinate;

  @override
  String toString() => '$chatOntology: no such channel: $coordinate';
}

/// A point in history this line does not carry. Not a refusal and not an empty
/// answer: the caller named a commit of some other channel, or mistyped one, and
/// reading the present instead would answer a question nobody asked.
final class NoSuchCommit implements Exception {
  const NoSuchCommit(this.coordinate, this.at);

  final String coordinate;
  final String at;

  @override
  String toString() => '$chatOntology: no such commit in $coordinate: $at';
}

/// A prefix short of unique. The candidates travel with it, because the answer
/// to *which one did you mean* is the list.
final class AmbiguousCommit implements Exception {
  const AmbiguousCommit(this.coordinate, this.at, this.candidates);

  final String coordinate;
  final String at;
  final List<String> candidates;

  @override
  String toString() => '$chatOntology: ambiguous commit in $coordinate: $at — '
      '${candidates.join(', ')}';
}

/// A body failed for a reason that is neither a decision nor a lost race: the
/// coordinate was wrong, the executable was missing, the machine said no.
final class ChatFailure implements Exception {
  const ChatFailure(this.function, this.reason, {required this.exitCode});

  final String function;
  final String reason;
  final int exitCode;

  @override
  String toString() => '$chatOntology: $function failed ($exitCode) — $reason';
}
