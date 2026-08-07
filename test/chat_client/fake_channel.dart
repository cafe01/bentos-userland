import 'package:bentos_userland/src/chat/channel.dart';
import 'package:bentos_userland/src/chat/handle.dart';
import 'package:bentos_userland/src/chat/model.dart';
import 'package:bentos_userland/src/chat/outcome.dart';

/// A [Channel] with no substrate underneath it — a script for the test to
/// hand `sync()` results to a [Room] with no `dart:io` anywhere in the tree.
final class FakeChannel implements Channel {
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
  Future<ActResult> join({String? displayName}) async => Acted('fake-join');

  @override
  Future<ActResult> leave() async => Acted('fake-leave');

  @override
  Future<ActResult> say(String body) async {
    final result = sayResult ?? Acted('fake-commit');
    if (result is Acted) spoken.add(body);
    return result;
  }

  @override
  Future<ActResult> setTopic(String text) async => Acted('fake-topic');

  @override
  Future<ActResult> away([String? reason]) async => Acted('fake-away');

  @override
  Future<ActResult> back() async => Acted('fake-back');

  @override
  Future<List<ChannelEvent>> sync() async => syncResult;
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
