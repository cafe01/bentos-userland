/// What a conversation is made of, declared once at the bottom.
///
/// A type declared in a face is a type the other faces have to re-invent, so
/// the shell face, the client and anything else built over this channel all
/// consume these and none of them invents its own.
library;

import 'handle.dart';

/// Someone in the channel, as the materialized roster holds them.
final class Participant {
  const Participant({
    required this.handle,
    required this.joined,
    this.displayName,
    this.away,
  });

  final Handle handle;

  /// When this participant entered. A seat torn down by `leave` takes the time
  /// with it, so a real return is dated afresh.
  final DateTime joined;

  final String? displayName;

  /// Null when present; the reason — **possibly empty** — when away.
  ///
  /// Presence is declared or absent and never simulated: the file exists when
  /// the participant is away and its contents are the reason, so absence is
  /// asked of the path and not of the bytes. An empty string is therefore
  /// *away, having said nothing*, and null is *here*.
  final String? away;

  bool get isAway => away != null;

  @override
  String toString() => '$handle${displayName == null ? '' : ' ($displayName)'}';
}

/// One utterance.
final class Message {
  const Message({
    required this.id,
    required this.author,
    required this.spoken,
    required this.body,
  });

  /// ULID: unique, time-sortable, and **never a position**. Concurrent
  /// utterances must collide neither on content nor on filename, which is what
  /// forbids a name that counts.
  final String id;

  final Handle author;

  /// When it was spoken. **Its position in the transcript is when it arrived**,
  /// and on two machines those are different facts.
  final DateTime spoken;

  final String body;
}

/// Who is in the channel — one listing of the materialized tree, never a walk
/// over the log. That is the whole reason the roster is a directory instead of
/// a fold: *who is here* is what a face asks on every redraw.
abstract interface class Roster {
  Iterable<Participant> get participants;

  /// By the name mentioned in prose. Null when nobody answers to it.
  Participant? byHandle(String local);

  bool contains(Handle handle);
}
