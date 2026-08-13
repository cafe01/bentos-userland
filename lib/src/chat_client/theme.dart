/// What a piece of the screen is *for* — never what it looks like.
///
/// Pure: no framework, no colour, no glyph. R5.7 asks that the distinctions
/// the screen draws come from one small vocabulary rather than a colour
/// picked at each call site, and a role is fixed here, at the same place the
/// fact it tags is already decided. What a role becomes on a terminal is the
/// render adapter's single table and nothing this file may know.
library;

import 'activity.dart';
import 'screen_model.dart';
import 'transcript.dart';

/// The closed set. Adding a member obliges the adapter's table, which is
/// exhaustive over this enum and does not compile until it is fed.
enum Role {
  /// Spoken text, the current room, the current tab — the terminal's own
  /// foreground, the one colour that cannot be wrong.
  primary,

  /// Timestamps, away reasons, the topic line, a tab that is not current.
  secondary,

  /// A mention. The loudest role, spent on one fact: look here.
  highlight,

  /// Reconnecting, refused, stumbled, an unrecognized command.
  warning,

  /// Frame and divider glyphs — never text, which is why it is the one role
  /// deliberately drawn below the contrast threshold text is held to.
  chrome,
}

/// The role of one transcript row.
///
/// Total, with no default arm: a new kind of line does not compile until
/// somebody gives it a role. [SystemLineKind] is the one split a role needs
/// that the line's own type does not already give — telling *you joined*
/// from *unknown command* without the adapter ever parsing the text.
Role roleOfLine(TranscriptLine line) => switch (line) {
  SpokenLine() => Role.primary,
  TopicLine() => Role.secondary,
  SystemLine(kind: SystemLineKind.notice) => Role.secondary,
  SystemLine(kind: SystemLineKind.warning) => Role.warning,
};

/// The role of one slot in the room bar, read off what the tab already
/// carries — no new field anywhere.
///
/// A mention outranks being current: the loudest role exists to say *look
/// here*, and a mention in the room already on screen is still the fact
/// worth pointing at.
Role roleOfTab(RoomTab tab) {
  if (tab.activityLevel == ActivityLevel.mention) return Role.highlight;
  return tab.isCurrent ? Role.primary : Role.secondary;
}
