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

/// Builds a channel at [name], over the bodies that write, the tree that
/// reads, and the doorbell [wait] wakes on — acting under [identity].
///
/// [cursor] is where a resuming client left off — null sees the conversation
/// whole. [attempts] is the bound handed down to the bodies; the retrying is
/// theirs, the bound is the caller's. [ticker] opens a fresh doorbell each
/// time [Channel.wait] is called, and [Channel.wait] disposes it when the
/// wait ends — a factory rather than one shared instance, so no two waits
/// fight over the same subscription's lifetime.
typedef ChannelConstruction = Channel Function({
  required String name,
  required ChatBodies bodies,
  required ChatTree tree,
  required Identity identity,
  required Ticker Function() ticker,
  String? cursor,
  int attempts,
});

/// What this library builds: a [LocalChannel] over the three seams.
Channel channelConstruction({
  required String name,
  required ChatBodies bodies,
  required ChatTree tree,
  required Identity identity,
  required Ticker Function() ticker,
  String? cursor,
  int attempts = defaultAttempts,
}) =>
    LocalChannel(
      name: name,
      bodies: bodies,
      tree: tree,
      identity: identity,
      ticker: ticker,
      cursor: cursor,
      attempts: attempts,
    );
