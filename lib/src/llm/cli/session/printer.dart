/// The printer: the face's answers, laid out for a terminal.
///
/// **This is where layout lives, and it lives nowhere else.** The face returns
/// what happened — speakers and blocks, a fold, a list of acts — and decides
/// nothing about indentation, width or the order of a footer. A register is a
/// skin of I/O over that, and this file is the skin's whole opinion.
///
/// Everything here is pure: values in, lines out, no process and no stream. That
/// is what makes it the one part of the register a test can hold.
library;

import '../../session/face.dart';
import '../../session/machine.dart';
import '../../session/primitive.dart';
import '../../session/transcript.dart';

/// How a speaker is named on screen. The words are the person's ontology —
/// `constitution` prints as `system` because that is what a person calls the
/// leading message — and the mapping is the register's, never the face's.
String labelOf(Speaker speaker) => switch (speaker) {
      Speaker.you => 'you',
      Speaker.agent => 'agent',
      Speaker.executor => 'executor',
      Speaker.constitution => 'system',
    };

/// The floor's own word for the state. Passed through rather than paraphrased:
/// `owes_inference` is what `fold` says, and a register that prettied it would
/// be teaching a person a vocabulary no other surface uses.
String stateWord(SessionState state) => switch (state) {
      SessionState.idle => 'idle',
      SessionState.owesInference => 'owes_inference',
      SessionState.owesResults => 'owes_results',
    };

/// The turns, one speaker per block, continuations aligned under the first.
List<String> renderTurns(List<RenderedTurn> turns) {
  final lines = <String>[];
  for (final turn in turns) {
    if (turn.blocks.isEmpty) continue;
    final label = labelOf(turn.speaker);
    final indent = ' ' * (label.length + 2);
    lines.add('$label: ${turn.blocks.first}');
    for (final extra in turn.blocks.skip(1)) {
      lines.add('$indent$extra');
    }
  }
  return lines;
}

/// The acts, as the audit lens shows them: sha, act, actor, and the sentence
/// where there is one. The sentence is the act's own and is never interpreted.
List<String> renderActs(List<Act> acts) => [
      for (final act in acts)
        [
          act.sha.value,
          act.name,
          act.actor,
          if (act.sentence != null) act.sentence!,
        ].join(' · '),
    ];

/// One screen: what is on it, and the state it was pinned at.
///
/// The footer carries the state because a transcript with no state under it
/// leaves a person unable to tell a finished turn from one still running — and
/// both were read at the same commit, which is the whole point of the pin.
List<String> renderScreen(Screen screen) => [
      ...screen.lens == Lens.audit
          ? renderActs(screen.acts)
          : renderTurns(screen.turns),
      '-- ${stateWord(screen.fold.state)}',
    ];
