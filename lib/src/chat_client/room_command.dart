/// What a slash command *means*, resolved from [InvokeCommand] before
/// anything acts on it. Pure — no `Channel`, no `Session`, no I/O.
library;

import 'intent.dart';

sealed class RoomCommand {
  const RoomCommand();
}

/// `/join` (current room) or `/join <coordinate>` (open, then join).
final class JoinRoom extends RoomCommand {
  const JoinRoom({this.coordinate, this.displayName});
  final String? coordinate;
  final String? displayName;
}

final class LeaveRoom extends RoomCommand {
  const LeaveRoom();
}

/// `/away` or `/away <reason words...>` — the words rejoined with single
/// spaces; null when none were given.
final class SetAway extends RoomCommand {
  const SetAway(this.reason);
  final String? reason;
}

final class SetBack extends RoomCommand {
  const SetBack();
}

/// Bare `/topic` — read, never write.
final class ShowTopic extends RoomCommand {
  const ShowTopic();
}

/// `/topic <text...>` — the words rejoined with single spaces.
final class SetTopic extends RoomCommand {
  const SetTopic(this.text);
  final String text;
}

final class ListChannels extends RoomCommand {
  const ListChannels();
}

final class ShowHelp extends RoomCommand {
  const ShowHelp();
}

/// A verb this face does not wire — R2.1's whole point: resolved to a value
/// rather than dropped, so `App` has something to render instead of nothing
/// to notice.
final class UnknownCommand extends RoomCommand {
  const UnknownCommand(this.verb, this.args);
  final String verb;
  final List<String> args;
}

RoomCommand resolveCommand(InvokeCommand intent) {
  final verb = intent.verb;
  final args = intent.args;
  switch (verb) {
    case 'join':
      return JoinRoom(coordinate: args.isEmpty ? null : args.first);
    case 'leave':
      return const LeaveRoom();
    case 'away':
      return SetAway(args.isEmpty ? null : args.join(' '));
    case 'back':
      return const SetBack();
    case 'topic':
      return args.isEmpty ? const ShowTopic() : SetTopic(args.join(' '));
    case 'list':
    case 'channels':
      return const ListChannels();
    case 'help':
      return const ShowHelp();
    default:
      return UnknownCommand(verb, args);
  }
}
