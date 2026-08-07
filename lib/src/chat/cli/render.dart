/// How the shell face draws what it read.
///
/// **None of this is the contract.** Whether a transcript shows a clock, how a
/// roster marks somebody away, what a topic change looks like — all of it is
/// this face's own choice, and another face over the same channel decides
/// otherwise without the medium learning that anything happened.
///
/// The register here is the scripted CLI, so the shapes are the ones a pipe can
/// read: one record per line, fields separated by tabs, and a body that spans
/// lines indented under its own header rather than folded into it.
library;

import '../model.dart';
import '../outcome.dart';

/// `@alfred⇥Alfred⇥here` · `@cafe⇥Café⇥away: at the dentist`
String rosterLine(Participant participant) => [
      '${participant.handle}',
      participant.displayName ?? '',
      participant.isAway
          ? (participant.away!.isEmpty ? 'away' : 'away: ${participant.away}')
          : 'here',
    ].join('\t');

/// `2026-08-06T12:00:00Z⇥@alfred⇥raising the install gate`
///
/// A body that spans lines keeps its shape: the first line rides the header and
/// the rest are indented, so a reader sees a paragraph and `cut -f3` still gets
/// the utterance's opening.
String messageLine(Message message) {
  final lines = message.body.split('\n');
  final header = [
    message.spoken.toUtc().toIso8601String(),
    '${message.author}',
    lines.first,
  ].join('\t');
  return [header, for (final line in lines.skip(1)) '\t\t$line'].join('\n');
}

/// What `monitor` prints when something lands. Speech is a transcript line;
/// everything else is a notice, marked so a reader can tell an utterance from a
/// fact about the room at a glance.
String eventLine(ChannelEvent event) => switch (event) {
      Spoke(:final message) => messageLine(message),
      TopicChanged(:final topic, :final by) => '— $by set the topic: $topic',
      RosterChanged(:final roster) => '— here: ${[
          for (final participant in roster.participants) '${participant.handle}'
        ].join(', ')}',
    };
