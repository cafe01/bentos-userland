/// `event` — every landing publishes, and something may be armed on it.
library;

import 'spine.dart';

final class Event {
  const Event({
    required this.entity,
    required this.instance,
    required this.point,
    required this.actor,
    required this.when,
    required this.say,
    required this.arrivedFrom,
  });

  final String entity;

  /// The instance that landed, or null when the class itself did.
  final String? instance;
  final Point point;
  final Actor actor;
  final Instant when;
  final String? say;

  /// The source it arrived from, or null when it was authored here (R2.4.1).
  final String? arrivedFrom;
}

/// An arming standing on this copy (R2.4.2). Local, travelling nowhere.
final class Registration {
  const Registration({
    required this.id,
    required this.command,
    required this.instance,
    required this.once,
  });
  final String id;
  final String command;

  /// The one instance armed on, or null for the whole entity.
  final String? instance;
  final bool once;
}

/// The slice of `Copy` this component owns.
abstract interface class CopyEvents {
  /// Run [command] for every landing that matches, until disarmed.
  Registration arm(String command, {String? instance});

  /// The same, once, then unregistered.
  Registration armOnce(String command, {String? instance});

  void disarm(String id);
  List<Registration> get armed;

  /// Live events, for a face that is standing. Never the mechanism by which
  /// an armed command runs.
  Stream<Event> listen({String? instance});
}
