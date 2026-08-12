import 'package:bentos_userland/src/chat/channel.dart';
import 'package:bentos_userland/src/chat/cli/floor.dart';
import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';
import 'package:bentos_userland/src/chat/seams.dart';
import 'package:bentos_userland/src/chat_client/ticker.dart';

/// A [Channel] with no substrate underneath it — a script for the test to
/// hand `sync()` results to a [Room] with no `dart:io` anywhere in the tree.
///
/// Not `final`: `_TopicChannel` in `app_test.dart` extends it to override one
/// method rather than reimplement the whole interface.
class FakeChannel implements Channel {
  FakeChannel({
    required this.name,
    required Handle me,
    this.sayResult,
  }) : _me = me;

  @override
  final String name;

  final Handle _me;

  /// What the next [say] returns — a caller sets this before calling.
  ActResult? sayResult;

  /// What the next [join]/[leave]/[away]/[back] returns — a caller sets
  /// these before calling, same pattern as [sayResult].
  ActResult? joinResult;
  ActResult? leaveResult;
  ActResult? awayResult;
  ActResult? backResult;

  /// Every body a caller [say]s, in order — the suite's window into what was
  /// actually sent.
  final List<String> spoken = [];

  /// What the next [sync] returns — a caller sets this before calling.
  List<ChannelEvent> syncResult = const [];

  @override
  String get coordinate => 'bentos.chat:$name';

  @override
  Handle get me => _me;

  @override
  String? get cursor => null;

  @override
  Future<String?> topic({String? at}) async => null;

  @override
  Future<Roster> roster({String? at}) async => const _EmptyRoster();

  @override
  Future<List<Message>> history({DateTime? since, DateTime? until, int? limit, String? at}) async => const [];

  @override
  Future<ActResult> join({String? displayName}) async =>
      joinResult ?? Acted('fake-join');

  @override
  Future<ActResult> leave() async => leaveResult ?? Acted('fake-leave');

  @override
  Future<ActResult> say(String body) async {
    final result = sayResult ?? Acted('fake-commit');
    if (result is Acted) spoken.add(body);
    return result;
  }

  @override
  Future<ActResult> setTopic(String text) async => Acted('fake-topic');

  @override
  Future<ActResult> away([String? reason]) async =>
      awayResult ?? Acted('fake-away');

  @override
  Future<ActResult> back() async => backResult ?? Acted('fake-back');

  @override
  Future<List<ChannelEvent>> sync() async => syncResult;

  @override
  Future<Arrival> wait({Duration? within, String? mentioning}) async =>
      throw UnimplementedError('not exercised by the client suite');
}

final class _EmptyRoster implements Roster {
  const _EmptyRoster();

  @override
  Iterable<Participant> get participants => const [];

  @override
  Participant? byHandle(String local) => null;

  @override
  bool contains(Handle handle) => false;
}

/// A [ChatFloor] with no substrate underneath it — the counterpart of
/// [FakeChannel] for whatever `App` needs beyond the rooms it started with:
/// minting a channel for a coordinate nobody opened yet, and answering which
/// coordinates a place carries.
final class FakeChatFloor implements ChatFloor {
  FakeChatFloor({Map<String, Channel>? channels, List<String>? available})
    : _channels = channels ?? {},
      available = available ?? (channels?.keys.toList() ?? const []);

  final Map<String, Channel> _channels;

  /// What [channels] answers — set independently of [_channels] because a
  /// coordinate can be listed as existing without this suite ever minting a
  /// live [Channel] for it.
  final List<String> available;

  /// Every place a channel was resolved from — the suite's window into
  /// whether the vantage a new room opens at is the one the session itself
  /// stands on.
  final List<String> requestedPlaces = [];

  void register(Channel channel) => _channels[channel.name] = channel;

  /// The client never asks who it is through the floor — it reads `me` off the
  /// channel it already holds — so this answers by refusing rather than by
  /// inventing a participant this suite would then quietly rely on.
  @override
  Identity get identity =>
      throw UnimplementedError('not exercised by the client suite');

  @override
  Channel channel(
    String name, {
    required String place,
    String? cursor,
    Identity? identity,
  }) {
    requestedPlaces.add(place);
    final existing = _channels[name];
    if (existing == null) {
      throw StateError('FakeChatFloor: no channel registered for $name');
    }
    return existing;
  }

  @override
  ChatBodies bodies(String name, {required String place, Identity? identity}) =>
      throw UnimplementedError('not exercised by the client suite');

  @override
  List<String> channels(String place) => List.of(available);

  @override
  Ticker dispatchTicker(String place) =>
      throw UnimplementedError('not exercised by the client suite');
}

final class FakeRoster implements Roster {
  const FakeRoster(this.participants);

  @override
  final List<Participant> participants;

  @override
  Participant? byHandle(String local) {
    for (final p in participants) {
      if (p.handle.local == local) return p;
    }
    return null;
  }

  @override
  bool contains(Handle handle) => participants.any((p) => p.handle == handle);
}
