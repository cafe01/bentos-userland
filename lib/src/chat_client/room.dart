/// Everything about being present at one conversation.
///
/// Wraps one [Channel] plus the local state a person accumulates around it:
/// the transcript, how loud it has been, what is half-typed. The channel is
/// an interface — nothing here reaches `dart:io`, and a suite drives a fake.
library;

import '../chat/channel.dart';
import '../chat/handle.dart';
import '../chat/model.dart';
import '../chat/mention.dart';
import '../chat/outcome.dart';
import 'activity.dart';
import 'composer.dart';
import 'transcript.dart';

final class Room {
  Room({
    required this.channel,
    String? persistedReadMark,
    List<String>? sentHistory,
    MentionScanner? mentionScanner,
  })  : transcript = Transcript(readMark: persistedReadMark),
        activity = Activity(),
        composer = Composer(sentHistory: sentHistory),
        mentionScanner = mentionScanner ?? MentionScanner(channel.me),
        _needsInitialCatchUp = persistedReadMark == null;

  final Channel channel;
  final Transcript transcript;
  final Activity activity;
  final Composer composer;
  final MentionScanner mentionScanner;

  Roster? _roster;
  String? _topic;

  /// True until this room's first fold — a room with no persisted mark opens
  /// caught up, so the initial load (whatever `sync()` hands back the first
  /// time, empty or a whole history) is marked read as soon as it lands,
  /// before anything after it is allowed to count as new noise.
  bool _needsInitialCatchUp;

  String get name => channel.name;

  String get coordinate => channel.coordinate;

  Handle get me => channel.me;

  Roster? get roster => _roster;

  String? get topic => _topic;

  /// Folds what [Channel.sync] returned into local state: [Spoke] appends and
  /// raises activity — louder when [mentionScanner] says this reader was
  /// named; [TopicChanged] appends a line and raises nothing, since a topic
  /// change is content and not noise about a person; [RosterChanged] replaces
  /// the roster and appends nothing, per the same rule.
  void fold(Iterable<ChannelEvent> events) {
    for (final event in events) {
      switch (event) {
        case Spoke(message: final message):
          transcript.append(SpokenLine(message));
          if (mentionScanner.mentions(message.body)) {
            activity.noteMention();
          } else {
            activity.noteSpoken();
          }
        case TopicChanged(topic: final topic, by: final by):
          _topic = topic;
          transcript.append(TopicLine(topic, by, DateTime.now()));
        case RosterChanged(roster: final newRoster):
          _roster = newRoster;
      }
    }

    if (_needsInitialCatchUp) {
      transcript.markRead();
      activity.clear();
      _needsInitialCatchUp = false;
    }
  }

  /// This room became the one the viewport shows, or was otherwise read:
  /// the noise clears and the mark advances to everything held.
  void enter() {
    activity.clear();
    transcript.markRead();
  }

  /// Speaks the composing buffer. Returns null when there is nothing to send
  /// — the buffer is whitespace-only and is left exactly as it was.
  ///
  /// **The buffer is only cleared on [Acted].** A [Refused] or a [Stumbled]
  /// must not eat what was typed: nothing is submitted to the channel until
  /// this call, so on anything but success the composer still holds the
  /// line, unmodified, ready to be sent again or edited.
  Future<ActResult?> speak() async {
    final body = composer.text;
    if (body.trim().isEmpty) return null;
    final result = await channel.say(body);
    if (result is Acted) composer.submit();
    return result;
  }
}
