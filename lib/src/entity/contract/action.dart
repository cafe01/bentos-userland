/// `action` — the only thing that changes an instance: the private area, the
/// compare-and-swap landing, the four outcomes, the gate.
library;

import 'dart:async';
import 'dart:io';

import 'spine.dart';

/// The slice of `Instance` this component owns.
abstract interface class InstanceActs {
  /// Open a private area at the instance's current point (R2.3.1). The point
  /// it opened at is what the landing compares against.
  Future<Act> beginAct({required Actor by});

  /// Convenience: open, run [body], land. The typed outcome of the landing is
  /// returned; nothing is thrown for a refusal, because all four outcomes are
  /// ordinary answers.
  Future<Outcome> act(
    FutureOr<void> Function(Act) body, {
    required Actor by,
    String? say,
    String? title,
  });
}

/// A private area of one instance, at one point. Writing here changes nothing
/// that any reader of this copy can see (R2.3.2).
abstract interface class Act {
  Directory get directory;
  Point get from;

  /// Land the whole of what was written, atomically, by compare-and-swap
  /// against [from].
  ///
  /// [say] is the one sentence of what was done; [title] sets the instance's
  /// displayed title and rides the landing as a trailer, which is what makes
  /// a far instance nameable with no content (R2.1.5).
  Future<Outcome> land({String? say, String? title});

  /// Throw the private area away. Nothing landed, nothing is left behind.
  void abandon();
}

/// The four outcomes of a landing (R2.3.5). A caller that ignores one fails
/// to compile rather than at three in the morning.
sealed class Outcome {
  const Outcome();
}

/// It landed. [action] is the record of it.
final class Landed extends Outcome {
  const Landed(this.action);
  final Action action;
}

/// The instance moved after this act began (R2.3.4). The actor may retry
/// as-is; nothing written is lost, and the private area still stands.
final class Moved extends Outcome {
  const Moved({required this.from, required this.now});
  final Point from;
  final Point now;
}

/// Two lines of this instance exist and neither contains the other (§2.7).
/// Nobody retries: a reconciliation is a new action.
final class DivergedFrom extends Outcome {
  const DivergedFrom({required this.here, required this.there});
  final Point here;
  final Point there;
}

/// A rule the entity declares refused it (R2.3.6). The same act is refused
/// again, and [words] are the rule's own.
final class Gated extends Outcome {
  const Gated({required this.rule, required this.words});
  final String rule;
  final String words;
}

/// The record of one landing.
final class Action {
  const Action({
    required this.point,
    required this.actor,
    required this.when,
    required this.say,
    required this.title,
    required this.arrivedFrom,
  });

  final Point point;
  final Actor actor;

  /// The date the action was taken. Preserved across arrival, never rewritten
  /// by the copy that received it (R2.6.4).
  final Instant when;

  /// The one sentence, if the actor gave one.
  final String? say;

  /// The instance's displayed title as of this landing, if it carried one.
  final String? title;

  /// The source this landing arrived from, or null if it was authored here.
  final String? arrivedFrom;
}
