/// The plug point: what builds a [Channel] over the two seams.
///
/// The contract suite is written against this signature and never against a
/// class, so the delivery is judged by the claims and not by its own shape.
library;

import 'channel.dart';
import 'handle.dart';
import 'local_channel.dart';
import 'seams.dart';
import '../chat_client/ticker.dart';

/// Builds a channel at [name], over the act bracket, the tree that reads, and
/// the doorbell [wait] wakes on — acting under [identity].
///
/// [cursor] is where a resuming client left off — null sees the conversation
/// whole. [attempts] is the bound the retry loop is held to — the loop and the
/// bound are both this library's, never the seam's. [ticker] opens a fresh
/// doorbell each time [Channel.wait] is called, and [Channel.wait] disposes it
/// when the wait ends — a factory rather than one shared instance, so no two
/// waits fight over the same subscription's lifetime. [clock] is one reading
/// of the wall clock, spent on every timestamp an act writes.
typedef ChannelConstruction = Channel Function({
  required String name,
  required ChatActs acts,
  required ChatTree tree,
  required Identity identity,
  required Ticker Function() ticker,
  String? cursor,
  int attempts,
  DateTime Function() clock,
});

/// What this library builds: a [LocalChannel] over the three seams.
Channel channelConstruction({
  required String name,
  required ChatActs acts,
  required ChatTree tree,
  required Identity identity,
  required Ticker Function() ticker,
  String? cursor,
  int attempts = defaultAttempts,
  DateTime Function() clock = DateTime.now,
}) =>
    LocalChannel(
      name: name,
      acts: acts,
      tree: tree,
      identity: identity,
      ticker: ticker,
      cursor: cursor,
      attempts: attempts,
      clock: clock,
    );
