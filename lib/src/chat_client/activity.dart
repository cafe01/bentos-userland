/// How loud a room is being — the fact the hotlist orders on.
///
/// **Speech only.** The hotlist answers "where is someone talking to me", so
/// [ActivityLevel.speech] and [ActivityLevel.mention] are raised by
/// [Activity.noteSpoken] and [Activity.noteMention] alone. A topic change
/// earns a [TranscriptLine][transcript.TranscriptLine]; a roster change earns
/// nothing here — presence churn in a busy room would drown the signal the
/// hotlist exists to carry.
library;

enum ActivityLevel { none, speech, mention }

final class Activity {
  Activity({this.level = ActivityLevel.none, this.count = 0});

  ActivityLevel level;
  int count;

  bool get isQuiet => level == ActivityLevel.none;

  /// Somebody spoke. Raises to [ActivityLevel.speech] unless a mention
  /// already outranks it — speech never demotes a mention already noted.
  void noteSpoken() {
    if (level == ActivityLevel.none) level = ActivityLevel.speech;
    count++;
  }

  /// Somebody named this reader — louder than plain speech, and never demoted
  /// back down by a later, unmarked line.
  void noteMention() {
    level = ActivityLevel.mention;
    count++;
  }

  /// The room is current, or was just read: the noise clears.
  void clear() {
    level = ActivityLevel.none;
    count = 0;
  }
}
